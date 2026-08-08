"""Promote Pipeline - Syncs an MLflow `champion` alias to a deployed model's
KServe manifest, via a PR rather than a direct push.

Shared platform script (baked into ml-platform-base, not any one project's
image) — used by the `promote-model` ClusterWorkflowTemplate (see
ArgoWorkflows/cluster-workflow-templates.yaml). It's project-agnostic: which
model, repo, branch, and manifest to touch are all passed in as CLI args by
the calling project's Argo Workflow, not hardcoded here.

Resolves the given model's `champion` alias's artifact location and, if it
changed, opens a PR updating the given KServe manifest's storageUri and
enables auto-merge, so the change goes through that project's own CI checks
before Argo CD (assuming selfHeal + automated sync) ever sees it.

A fresh clone is used rather than editing any project's working copy: this
script runs in a container built from a Docker image (COPY . .), not a live
git checkout, so there's no commit history to push against locally.

Requires `gh` (installed alongside this script in base-image/Dockerfile)
authenticated via the GH_TOKEN env var, and the target repo's "Allow
auto-merge" setting plus a required status check on the base branch —
otherwise `gh pr merge --auto` merges with nothing to wait on.
"""

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


def get_champion_source_uri(model_name: str) -> tuple[str, str]:
    """Resolve the artifact location the `champion` alias currently points to."""
    client = MlflowClient()
    version = client.get_model_version_by_alias(model_name, "champion")
    if not version.source:
        raise ValueError(f"Champion version {version.version} of {model_name} has no source URI")
    logger.info(f"Champion is {model_name} v{version.version} (run {version.run_id})")
    return version.version, version.source


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


def run(args: list[str], cwd: Path) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)
    return result.stdout.strip()


@app.command()
def promote(
    model_name: str = typer.Option(..., "--model-name"),
    repo: str = typer.Option(..., "--repo"),
    base_branch: str = typer.Option(..., "--base-branch"),
    yaml_relpath: str = typer.Option(..., "--yaml-relpath"),
    clone_dir: str = "/tmp/gitops-promote",
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
    authed_url = f"https://github.com/{repo}.git".replace(
        "https://", f"https://x-access-token:{token}@"
    )

    clone_path = Path(clone_dir)
    if clone_path.exists():
        shutil.rmtree(clone_path)

    run(
        ["git", "clone", "--branch", base_branch, "--depth", "1", authed_url, str(clone_path)],
        cwd=clone_path.parent,
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
    run(["git", "push", "origin", promote_branch], cwd=clone_path)

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
