"""Tests for MLflowExperimentLogger, against a local file-based tracking store."""

import mlflow
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from mlops_toolkit.tracking.experiment_logger import MLflowExperimentLogger


@pytest.fixture(autouse=True)
def local_tracking_uri(tmp_path, monkeypatch):
    # sqlite, not a plain file store: model registry (registered models,
    # aliases) needs a database-backed store in modern MLflow. chdir into
    # tmp_path too, since both mlflow's default artifact root and
    # _log_confusion_matrix's plt.savefig("confusion_matrix.png") resolve
    # relative to cwd rather than the tracking URI.
    monkeypatch.chdir(tmp_path)
    mlflow.set_tracking_uri(f"sqlite:///{tmp_path / 'mlflow.db'}")


@pytest.fixture
def trained_pipeline():
    X = pd.DataFrame({"a": [1.0, 2.0, 3.0, 4.0], "b": [4.0, 3.0, 2.0, 1.0]})
    y = pd.Series([0, 1, 0, 1])
    pipeline = Pipeline([("scaler", StandardScaler()), ("classifier", LogisticRegression())])
    pipeline.fit(X, y)
    return pipeline, X


def test_log_training_run_returns_run_id_and_logs_metrics(trained_pipeline):
    pipeline, X = trained_pipeline
    experiment_logger = MLflowExperimentLogger("test-experiment", model_name="test-model")

    run_id = experiment_logger.log_training_run(
        pipeline=pipeline,
        X_train=X,
        X_test=X,
        metrics={"accuracy": 0.9},
        confusion_matrix=None,
        feature_metadata={"feature_version": "v1", "total_columns": 2},
    )

    assert run_id is not None
    run = mlflow.get_run(run_id)
    assert run.data.metrics["accuracy"] == 0.9
    assert run.data.params["algorithm"] == "LogisticRegression"
    assert run.data.params["feature_version"] == "v1"


def test_get_champion_score_returns_none_without_a_champion(trained_pipeline):
    experiment_logger = MLflowExperimentLogger("test-experiment", model_name="unregistered-model")
    assert experiment_logger.get_champion_score("accuracy") is None


def test_promote_to_champion_sets_alias_and_score_becomes_visible(trained_pipeline):
    pipeline, X = trained_pipeline
    experiment_logger = MLflowExperimentLogger("test-experiment", model_name="test-model-2")

    run_id = experiment_logger.log_training_run(
        pipeline=pipeline,
        X_train=X,
        X_test=X,
        metrics={"accuracy": 0.9},
        confusion_matrix=None,
        feature_metadata={},
    )

    assert experiment_logger.get_champion_score("accuracy") is None

    experiment_logger.promote_to_champion(run_id)

    assert experiment_logger.get_champion_score("accuracy") == 0.9


def test_promote_to_champion_on_unknown_run_warns_without_raising(caplog):
    experiment_logger = MLflowExperimentLogger("test-experiment", model_name="test-model-3")
    experiment_logger.promote_to_champion("not-a-real-run-id")
    assert experiment_logger.get_champion_score("accuracy") is None
