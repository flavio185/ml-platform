"""Tests for trainer."""

import pandas as pd
import pytest
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from mlops_toolkit.modeling.pipeline_builder import create_sklearn_pipeline
from mlops_toolkit.modeling.trainer import train_and_evaluate, train_model


def build_preprocessor(X: pd.DataFrame) -> ColumnTransformer:
    numeric_cols = [c for c in X.columns if X[c].dtype in ["int64", "float64"]]
    return ColumnTransformer(transformers=[("num", StandardScaler(), numeric_cols)])


def fake_evaluate(pipeline, X_test, y_test):
    """Stands in for a project's task-specific evaluate_model."""
    y_pred = pipeline.predict(X_test)
    accuracy = (y_pred == y_test.to_numpy()).mean()
    return {"accuracy": accuracy}, "confusion-matrix-placeholder", y_pred


@pytest.fixture
def sample_train_data():
    X_train = pd.DataFrame(
        {"a": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0], "b": [6.0, 5.0, 4.0, 3.0, 2.0, 1.0]}
    )
    y_train = pd.Series([0, 0, 1, 1, 0, 1])
    return X_train, y_train


@pytest.fixture
def sample_test_data():
    X_test = pd.DataFrame({"a": [1.5, 5.5], "b": [5.5, 1.5]})
    y_test = pd.Series([0, 1])
    return X_test, y_test


def test_train_model_returns_fitted_pipeline(sample_train_data):
    X_train, y_train = sample_train_data
    pipeline = create_sklearn_pipeline(X_train, LogisticRegression(), build_preprocessor)

    trained = train_model(pipeline, X_train, y_train)

    assert isinstance(trained, Pipeline)
    assert hasattr(trained, "classes_")


def test_train_and_evaluate_uses_injected_evaluate_fn(sample_train_data, sample_test_data):
    X_train, y_train = sample_train_data
    X_test, y_test = sample_test_data
    pipeline = create_sklearn_pipeline(X_train, LogisticRegression(), build_preprocessor)

    trained, metrics, cm, extra = train_and_evaluate(
        pipeline, X_train, y_train, X_test, y_test, evaluate_fn=fake_evaluate
    )

    assert isinstance(trained, Pipeline)
    assert "accuracy" in metrics
    assert cm == "confusion-matrix-placeholder"
    assert len(extra) == len(X_test)


def test_train_and_evaluate_fits_before_evaluating(sample_train_data, sample_test_data):
    X_train, y_train = sample_train_data
    X_test, y_test = sample_test_data
    pipeline = create_sklearn_pipeline(X_train, LogisticRegression(), build_preprocessor)

    seen_fitted = []

    def spy_evaluate(pipeline, X_test, y_test):
        seen_fitted.append(hasattr(pipeline, "classes_"))
        return {}, None, None

    train_and_evaluate(pipeline, X_train, y_train, X_test, y_test, evaluate_fn=spy_evaluate)

    assert seen_fitted == [True]
