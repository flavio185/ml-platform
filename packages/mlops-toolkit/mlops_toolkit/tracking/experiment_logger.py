"""MLflow logging utilities.

This is ml-default-payment-project's version of MLflowExperimentLogger,
which is the one with champion/promote logic — iris-project's copy never
got that backported, so it's the source of truth here. The one change from
that source: MODEL_NAME was a module-level constant, hardcoded per project.
It's now a constructor argument, since which name a project registers under
is exactly the kind of thing that should vary without editing this file.
"""

from loguru import logger
from matplotlib import pyplot as plt
import mlflow
from mlflow.models import infer_signature
import mlflow.sklearn
import pandas as pd
from sklearn.pipeline import Pipeline


class MLflowExperimentLogger:
    """Handles MLflow logging for model training experiments.

    Every algorithm trained for a project is registered under the same
    `model_name` (rather than each algorithm getting its own registered
    model), so each training run adds a new *version* under that name and a
    single stable `models:/{model_name}@champion` reference always resolves
    to whichever algorithm/version currently performs best.
    """

    def __init__(self, experiment_name: str, model_name: str):
        """Initialize MLflow experiment logger.

        Args:
            experiment_name: Name of MLflow experiment
            model_name: Registered model name every training run's model
                version is added under (e.g. "default-payment-predictor")
        """
        self.experiment_name = experiment_name
        self.model_name = model_name
        mlflow.set_experiment(experiment_name)
        logger.info(f"MLflow experiment set to: {experiment_name}")

    def log_training_run(
        self,
        pipeline: Pipeline,
        X_train: pd.DataFrame,
        X_test: pd.DataFrame,
        metrics: dict,
        confusion_matrix,
        feature_metadata: dict,
        run_name: str | None = None,
        dataset_uri: str | None = None,
        dataset_version_id: str | None = None,
        dataset_last_modified: str | None = None,
    ) -> str:
        """Log a complete training run to MLflow.

        Args:
            pipeline: Trained sklearn pipeline
            X_train: Training features
            X_test: Test features
            metrics: Evaluation metrics dictionary
            confusion_matrix: Confusion matrix plot
            feature_metadata: Feature metadata dictionary
            run_name: Optional name for the run
            dataset_uri: URI of the exact dataset snapshot training used
                (e.g. the Gold parquet), for lineage tracking. Pass what the
                caller actually resolved/read -- this module has no way to
                determine that on its own -- omit if unknown.
            dataset_version_id: Version identifier for `dataset_uri` (e.g.
                an S3 object version ID)
            dataset_last_modified: Last-modified timestamp for `dataset_uri`

        Returns:
            The run ID, for champion comparison/promotion by the caller.
        """
        algorithm = pipeline.steps[-1][1].__class__.__name__

        with mlflow.start_run(run_name=run_name or algorithm):
            self._log_data_params(X_train, X_test)
            mlflow.log_param("algorithm", algorithm)
            self._log_feature_params(feature_metadata)
            mlflow.log_metrics(metrics)
            self._log_confusion_matrix(confusion_matrix)
            mlflow.log_dict(feature_metadata, "feature_metadata.json")
            self._log_dataset_metadata(
                dataset_uri=dataset_uri,
                dataset_version_id=dataset_version_id,
                dataset_last_modified=dataset_last_modified,
            )
            self._log_model(pipeline, X_train, algorithm)

            run_id = mlflow.active_run().info.run_id
            logger.success(f"MLflow run logged successfully. Run ID: {run_id}")
            return run_id

    def get_champion_score(self, metric_name: str) -> float | None:
        """Return the current champion's value for metric_name.

        Returns None if no champion alias exists yet (first-ever training
        run), so callers can distinguish "no champion to beat" from "champion
        scored 0".
        """
        client = mlflow.tracking.MlflowClient()
        try:
            champion_version = client.get_model_version_by_alias(self.model_name, "champion")
        except mlflow.exceptions.MlflowException:
            return None

        run = client.get_run(champion_version.run_id)
        return run.data.metrics.get(metric_name)

    def promote_to_champion(self, run_id: str) -> None:
        """Set the `champion` alias on the model version produced by run_id.

        Args:
            run_id: Run ID of the winning candidate (already logged via
                log_training_run, so its model version already exists).
        """
        client = mlflow.tracking.MlflowClient()
        versions = [
            v
            for v in client.search_model_versions(f"run_id='{run_id}'")
            if v.name == self.model_name
        ]
        if not versions:
            logger.warning(
                f"No registered version of '{self.model_name}' found for run {run_id}; "
                "skipping champion promotion"
            )
            return

        version = versions[0].version
        client.set_registered_model_alias(self.model_name, "champion", version)
        logger.success(f"Promoted {self.model_name} v{version} (run {run_id}) to champion")

    def _log_data_params(self, X_train: pd.DataFrame, X_test: pd.DataFrame):
        """Log data-related parameters."""
        mlflow.log_param("train_size", X_train.shape[0])
        mlflow.log_param("test_size", X_test.shape[0])
        mlflow.log_param("n_features", X_train.shape[1])

    def _log_feature_params(self, feature_metadata: dict):
        """Log feature-related parameters."""
        mlflow.log_param("feature_version", feature_metadata.get("feature_version", "unknown"))
        mlflow.log_param("total_features", feature_metadata.get("total_columns"))
        mlflow.log_param(
            "engineered_features_count",
            len(feature_metadata.get("engineered_features", [])),
        )

        engineered_features = feature_metadata.get("engineered_features", [])
        if engineered_features:
            mlflow.log_param("engineered_features", ",".join(engineered_features))

    def _log_confusion_matrix(self, cm):
        """Log confusion matrix plot."""
        plt.savefig("confusion_matrix.png")
        mlflow.log_artifact("confusion_matrix.png")
        plt.close()

    def _log_dataset_metadata(
        self,
        dataset_uri: str | None,
        dataset_version_id: str | None,
        dataset_last_modified: str | None,
    ):
        """Log lineage for the exact dataset snapshot training used.

        The only thing a drift check (or a human reading the run) needs to
        trust as "what was this trained on" -- not logged at all if the
        caller doesn't have it.
        """
        if dataset_uri is not None:
            mlflow.log_params(
                {
                    "dataset_uri": dataset_uri,
                    "dataset_version_id": dataset_version_id or "unknown",
                    "dataset_last_modified": dataset_last_modified or "unknown",
                }
            )

    def _log_model(self, pipeline: Pipeline, X_train: pd.DataFrame, algorithm: str):
        """Log the trained model to MLflow."""
        signature = infer_signature(X_train, pipeline.predict(X_train))

        mlflow.sklearn.log_model(
            pipeline,
            artifact_path=algorithm,
            registered_model_name=self.model_name,
            signature=signature,
            input_example=X_train.head(3),
        )

        logger.info(f"Model registered: {self.model_name} ({algorithm})")
