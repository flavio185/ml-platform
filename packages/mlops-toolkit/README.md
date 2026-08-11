# mlops-toolkit

Shared training, tracking, and pipeline plumbing for sklearn + MLflow
projects on this platform — extracted from the infrastructure code
`iris-project` and `ml-default-payment-project` independently rebuilt
identically. Sibling package to `ml-platform/packages/mlops-promote`, which
picks up where this leaves off: it reads the `champion` alias that
`MLflowExperimentLogger.promote_to_champion` sets here and opens a PR
pointing a KServe manifest at it.

## What's in here (v0.1 — byte-identical extraction pass)

- **`mlops_toolkit.modeling`** — `train_model` / `train_and_evaluate` and
  `create_sklearn_pipeline` / `get_pipeline_info`. Task-agnostic: evaluation
  is injected via `evaluate_fn`, preprocessing via `preprocessor_builder`,
  so this module doesn't need to know whether it's training a classifier or
  a regressor, or what columns a project's features have.
- **`mlops_toolkit.tracking.MLflowExperimentLogger`** — logs a training run
  (params, metrics, confusion matrix, feature/dataset lineage, model
  registration) and owns champion comparison/promotion
  (`get_champion_score` / `promote_to_champion`) against a single
  registered model name passed in at construction.
- **`mlops_toolkit.io`** — `wait_for_s3_object`, `get_dataset_metadata`,
  `save_feature_metadata`: the S3 versioning/lineage helpers a feature
  pipeline needs around its Gold-layer write.

Deliberately **not** in this pass: task-specific evaluation (binary vs.
multiclass vs. regression metrics), model factories/hyperparameters,
preprocessing column logic, the `s3://` vs. local path branching still
duplicated across each project's own `preprocessing.py` / `data_loader.py`
/ `inference_pipeline.py`, and full pipeline orchestration (feature /
training / inference entrypoints). Those still fork meaningfully between
projects, or need a real design (see the extraction plan's
`TaskEvaluator` strategy) rather than a copy-paste move.

## Usage

Installed the same way as `mlops-promote` — a normal dependency pinned via
git subdirectory (switch to a tag once this stabilizes, same as that
package's own note about floating on `@main`):

```toml
dependencies = [
    "mlops-toolkit @ git+https://github.com/flavio185/ml-platform@main#subdirectory=packages/mlops-toolkit",
]
```

```python
from mlops_toolkit.modeling import create_sklearn_pipeline, train_and_evaluate
from mlops_toolkit.tracking import MLflowExperimentLogger

pipeline = create_sklearn_pipeline(X_train, model, preprocessor_builder=build_preprocessor)
trained, metrics, cm, extra = train_and_evaluate(
    pipeline, X_train, y_train, X_test, y_test, evaluate_fn=evaluate_model
)

experiment_logger = MLflowExperimentLogger("baseline-models", model_name="default-payment-predictor")
run_id = experiment_logger.log_training_run(trained, X_train, X_test, metrics, cm, feature_metadata)

champion_score = experiment_logger.get_champion_score("roc_auc")
if champion_score is None or metrics["roc_auc"] > champion_score:
    experiment_logger.promote_to_champion(run_id)
```

`evaluate_model` and `build_preprocessor` above stay project-owned for now
— they're the parts of iris-project and ml-default-payment-project that
still genuinely differ (multiclass vs. binary metrics, numeric-only vs.
categorical+numeric columns).
