# mlops-promote

Opens a PR pointing a KServe manifest's `storageUri` at the current MLflow
`champion` alias, and enables auto-merge so it lands once the target repo's
own CI checks pass — used by the `promote-model` `ClusterWorkflowTemplate`
(see `ml-platform/ArgoWorkflows/cluster-workflow-templates.yaml` and
`kubernetes-gitops/argo-workflows/cluster-workflow-templates.yaml`).

Deliberately a small, independently-versioned package rather than something
baked into `ml-platform-base`: it's project logic that iterates quickly
(unlike `feast`/`mlflow`/`ray`, which are genuinely stable, infrequently
changing platform dependencies), so it shouldn't force a base-image rebuild
plus a downstream project-image rebuild on every change. A consuming
project just bumps a `pyproject.toml`/`uv.lock` pin.

## Usage

Installed as a normal dependency (see any consuming project's
`pyproject.toml`), it exposes a console script:

```
promote-model \
  --model-name default-payment-predictor \
  --repo flavio185/ml-default-payment-project \
  --base-branch feature/three-pipeline-architecture \
  --yaml-relpath gitops/kserve-inference.yaml
```

Requires `gh` on PATH (platform-provided, in `ml-platform-base`) authenticated
via the `GH_TOKEN` env var, and `MLFLOW_TRACKING_URI` pointing at the calling
project's MLflow instance.
