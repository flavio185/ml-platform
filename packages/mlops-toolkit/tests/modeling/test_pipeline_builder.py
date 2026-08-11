"""Tests for pipeline_builder."""

import pandas as pd
import pytest
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from mlops_toolkit.modeling.pipeline_builder import create_sklearn_pipeline, get_pipeline_info


def build_preprocessor(X: pd.DataFrame) -> ColumnTransformer:
    numeric_cols = [c for c in X.columns if X[c].dtype in ["int64", "float64"]]
    return ColumnTransformer(transformers=[("num", StandardScaler(), numeric_cols)])


@pytest.fixture
def sample_data():
    return pd.DataFrame(
        {
            "a": [1.0, 2.0, 3.0, 4.0],
            "b": [4.0, 3.0, 2.0, 1.0],
        }
    )


def test_create_sklearn_pipeline_returns_pipeline(sample_data):
    pipeline = create_sklearn_pipeline(sample_data, LogisticRegression(), build_preprocessor)
    assert isinstance(pipeline, Pipeline)


def test_create_sklearn_pipeline_has_two_named_steps(sample_data):
    pipeline = create_sklearn_pipeline(sample_data, LogisticRegression(), build_preprocessor)
    assert [name for name, _ in pipeline.steps] == ["preprocessor", "classifier"]


def test_create_sklearn_pipeline_passes_x_train_to_builder(sample_data):
    seen = []

    def tracking_builder(X):
        seen.append(X)
        return build_preprocessor(X)

    create_sklearn_pipeline(sample_data, LogisticRegression(), tracking_builder)

    assert len(seen) == 1
    assert seen[0] is sample_data


def test_pipeline_fits_and_predicts(sample_data):
    pipeline = create_sklearn_pipeline(
        sample_data, RandomForestClassifier(n_estimators=5, random_state=42), build_preprocessor
    )
    y = pd.Series([0, 1, 0, 1])
    pipeline.fit(sample_data, y)

    predictions = pipeline.predict(sample_data)
    assert len(predictions) == len(sample_data)


def test_get_pipeline_info(sample_data):
    pipeline = create_sklearn_pipeline(sample_data, LogisticRegression(), build_preprocessor)
    y = pd.Series([0, 1, 0, 1])
    pipeline.fit(sample_data, y)

    info = get_pipeline_info(pipeline)
    assert info["steps"] == ["preprocessor", "classifier"]
    assert info["classifier"] == "LogisticRegression"
    assert "num" in info["transformers"]
