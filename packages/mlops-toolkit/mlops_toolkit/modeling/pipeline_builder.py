"""Pipeline builder for creating sklearn pipelines.

Byte-identical between iris-project and ml-default-payment-project except
for one thing: both versions imported their preprocessor builder from a
project-specific `features.preprocessing` module. That column-selection
logic (numeric-only vs. categorical+numeric) is genuine per-project
variation, so it's injected here instead of imported, which is the only
change from either source.
"""

from collections.abc import Callable

from loguru import logger
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline

PreprocessorBuilder = Callable[[pd.DataFrame], ColumnTransformer]


def create_sklearn_pipeline(
    X_train: pd.DataFrame, model, preprocessor_builder: PreprocessorBuilder
) -> Pipeline:
    """Create sklearn pipeline with preprocessing and model.

    Args:
        X_train: Training features, passed to preprocessor_builder
        model: Sklearn model instance
        preprocessor_builder: Callable that builds a ColumnTransformer from
            X_train (a project's own `build_preprocessor`)

    Returns:
        Pipeline with preprocessor and model
    """
    logger.info(f"Building pipeline with {model.__class__.__name__}")

    pipeline = Pipeline(
        steps=[
            ("preprocessor", preprocessor_builder(X_train)),
            ("classifier", model),
        ]
    )

    return pipeline


def get_pipeline_info(pipeline: Pipeline) -> dict:
    """Extract information about the pipeline."""
    info = {
        "steps": [step[0] for step in pipeline.steps],
        "classifier": pipeline.steps[-1][1].__class__.__name__,
        "n_features_in": getattr(pipeline, "n_features_in_", None),
    }

    preprocessor = pipeline.named_steps.get("preprocessor")
    if preprocessor:
        info["transformers"] = [name for name, _, _ in preprocessor.transformers]

    return info
