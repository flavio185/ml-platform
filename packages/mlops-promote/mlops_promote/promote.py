"""Promote Pipeline - Syncs an MLflow `champion` alias to a deployed model's
KServe manifest, via a PR rather than a direct push.

Distributed as an installable package (not baked into ml-platform-base) so
that changes here only require the consuming project to bump a
pyproject.toml/uv.lock pin and rebuild its own image — not a base-image
rebuild followed by a project-image rebuild. It's project-agnostic: which
model, repo, branch, and manifest to touch are all passed in as CLI args by
the calling project's Argo Workflow, not hardcoded here.

Resolves the given model's `champion` alias's artifact location and, if it
changed, opens a PR updating the given KServe manifest's storageUri and
enables auto-merge, so the change goes through that project's own CI checks
before Argo CD (assuming selfHeal + automated sync) ever sees it.

A fresh clone is used rather than editing any project's working copy: this
script runs in a container built from a Docker image (COPY . .), not a live
git checkout, so there's no commit history to push against locally.

Requires `gh` (platform-provided, in ml-platform-base) authenticated via the
GH_TOKEN env var, and the target repo's "Allow auto-merge" setting plus a
required status check on the base branch — otherwise `gh pr merge --auto`
merges with nothing to wait on.
"""

import base64
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from loguru import logger
from mlflow.tracking import MlflowClient
import typer

app = typer.Typer()

STORAGE_URI_PATTERN = re.compile(r'(storageUri:\s*")([^"]+)(")')
# Matches the branch names this script creates (promote_branch below), capturing
# the epoch timestamp suffix so branches can be ordered by recency without an
# extra API call per branch.
PROMOTE_BRANCH_PATTERN = re.compile(r"^promote/champion-v.+-(\d+)$")


def get_champion_source_uri(model_name: str) -> tuple[str, str]:
    """Resolve the artifact location the `champion` alias currently points to."""
    client = MlflowClient()
    version = client.get_model_version_by_alias(model_name, "champion")
    if not version.source:
        raise ValueError(f"Champion version {version.version} of {model_name} has no source URI")

    source = version.source
    if source.startswith("models:/"):
        # MLflow 3.x's "Logged Model" registry (what mlflow.<flavor>.log_model(...,
        # name=...) registers through) reports a logical models:/<model_id> reference
        # here, not a resolvable storage URI. KServe's storage-initializer only
        # understands gs://, s3://, file://, http(s)://, hf:// — models:/ fails with
        # "Cannot recognize storage type". Resolve to the actual artifact location via
        # the LoggedModel entity instead.
        model_id = source.removeprefix("models:/")
        logged_model = client.get_logged_model(model_id)
        source = logged_model.artifact_location
        logger.info(f"Resolved {version.source} -> {source}")

    logger.info(f"Champion is {model_name} v{version.version} (run {version.run_id})")
    return version.version, source


def update_storage_uri(yaml_path: Path, new_uri: str) -> bool:
    """Rewrite the storageUri field in place. Returns False if already current."""
    text = yaml_path.read_text()
    match = STORAGE_URI_PATTERN.search(text)
    if not match:
        raise ValueError(f"No storageUri field found in {yaml_path}")

    if match.group(2) == new_uri:
        return False

    text = STORAGE_URI_PATTERN.sub(rf"\g<1>{new_uri}\g<3>", text, count=1)
    yaml_path.write_text(text)
    return True


def run(args: list[str], cwd: Path, env: dict | None = None) -> str:
    """Run a command, logging stderr before raising so Argo logs show *why*
    a failure happened, not just that it did."""
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        logger.error(f"Command failed: {' '.join(args)}\nstderr: {result.stderr.strip()}")
        result.check_returncode()
    return result.stdout.strip()


def prune_old_promote_branches(repo_url: str, clone_path: Path, auth_env: dict, keep: int) -> None:
    """Delete promote branches beyond the `keep` most recent.

    `gh pr merge --auto --delete-branch` only deletes a branch once its PR
    actually merges — a PR stuck on a failing/missing required check (or
    superseded by a newer promote run before anyone looks at it) leaves its
    branch behind forever. Left unchecked that's unbounded branch/PR clutter
    on every promote run, so this prunes down to the most recent `keep`
    (ordered by the timestamp already embedded in each branch name) every
    time a new one is pushed. Deleting a branch with an open PR just closes
    that PR unmerged, which is correct here: once newer promote attempts
    exist, an older one is stale by definition.
    """
    output = run(
        ["git", "ls-remote", "--heads", repo_url, "promote/champion-v*"],
        cwd=clone_path,
        env=auth_env,
    )
    branches = []
    for line in output.splitlines():
        if not line.strip():
            continue
        ref = line.split("\t", 1)[1]
        name = ref.removeprefix("refs/heads/")
        match = PROMOTE_BRANCH_PATTERN.match(name)
        if match:
            branches.append((int(match.group(1)), name))

    branches.sort(reverse=True)  # newest (highest timestamp) first
    for _, name in branches[keep:]:
        logger.info(f"Pruning old promote branch {name}")
        run(["git", "push", "origin", "--delete", name], cwd=clone_path, env=auth_env)


def git_auth_env(token: str) -> dict:
    """Env vars that authenticate git's HTTPS transport without the token ever
    appearing in argv or a remote URL — both of which git will happily echo
    back into stdout/stderr (and therefore Argo/Grafana logs) on an auth
    failure. Same mechanism actions/checkout uses."""
    basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    return {
        **os.environ,
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "http.https://github.com/.extraheader",
        "GIT_CONFIG_VALUE_0": f"AUTHORIZATION: basic {basic}",
    }


@app.command()
def promote(
    model_name: str = typer.Option(..., "--model-name"),
    repo: str = typer.Option(..., "--repo"),
    base_branch: str = typer.Option(..., "--base-branch"),
    yaml_relpath: str = typer.Option(..., "--yaml-relpath"),
    clone_dir: str = "/tmp/gitops-promote",
    keep_branches: int = typer.Option(
        2, "--keep-branches", help="Number of most-recent promote/champion-* branches to retain"
    ),
):
    """Open a PR pointing a KServe manifest's storageUri at the current
    MLflow champion, and enable auto-merge so it lands once CI passes.

    All required arguments are passed in by the calling Argo template (see
    ArgoWorkflows/cluster-workflow-templates.yaml's `promote-model`
    ClusterWorkflowTemplate) rather than defaulted here, so each project's
    own Workflow owns what gets promoted, not this script.
    """
    version, champion_uri = get_champion_source_uri(model_name)

    # Also picked up automatically by `gh` (GH_TOKEN/GITHUB_TOKEN) below.
    token = os.environ["GH_TOKEN"]
    auth_env = git_auth_env(token)
    repo_url = f"https://github.com/{repo}.git"

    clone_path = Path(clone_dir)
    if clone_path.exists():
        shutil.rmtree(clone_path)

    run(
        ["git", "clone", "--branch", base_branch, "--depth", "1", repo_url, str(clone_path)],
        cwd=clone_path.parent,
        env=auth_env,
    )

    yaml_path = clone_path / yaml_relpath
    if not update_storage_uri(yaml_path, champion_uri):
        logger.info("storageUri already points at the current champion; nothing to promote")
        return

    promote_branch = f"promote/champion-v{version}-{int(time.time())}"
    run(["git", "checkout", "-b", promote_branch], cwd=clone_path)
    run(["git", "config", "user.name", "argo-promote-bot"], cwd=clone_path)
    run(
        ["git", "config", "user.email", "argo-promote-bot@users.noreply.github.com"],
        cwd=clone_path,
    )
    run(["git", "add", yaml_relpath], cwd=clone_path)
    run(
        [
            "git",
            "commit",
            "-m",
            f"promote: point storageUri at champion v{version} ({champion_uri})",
        ],
        cwd=clone_path,
    )
    run(["git", "push", "origin", promote_branch], cwd=clone_path, env=auth_env)
    prune_old_promote_branches(repo_url, clone_path, auth_env, keep=keep_branches)

    pr_url = run(
        [
            "gh",
            "pr",
            "create",
            "--repo",
            repo,
            "--base",
            base_branch,
            "--head",
            promote_branch,
            "--title",
            f"promote: champion v{version}",
            "--body",
            f"Automated promotion by the `promote` DAG step.\n\n"
            f"storageUri -> `{champion_uri}`\n\n"
            f"Auto-merges once CI checks pass.",
        ],
        cwd=clone_path,
    )
    logger.success(f"Opened {pr_url}")

    run(["gh", "pr", "merge", pr_url, "--auto", "--squash", "--delete-branch"], cwd=clone_path)
    logger.success("Auto-merge enabled; PR will merge once CI checks pass")


if __name__ == "__main__":
    app()
