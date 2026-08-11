"""Model training utilities.

train_model is unchanged from either source project. train_and_evaluate
takes its evaluator as an argument rather than importing a project's
`evaluate_model` directly: iris and payment already diverge there (binary
vs. multiclass metrics), and a regression project would diverge further
still, so this module stays task-agnostic and lets the caller supply the
task-specific piece.
"""

from collections.abc import Callable

from loguru import logger
import pandas as pd
from sklearn.pipeline import Pipeline

EvaluateFn = Callable[[Pipeline, pd.DataFrame, pd.Series], tuple[dict, object, object]]


def train_model(pipeline: Pipeline, X_train: pd.DataFrame, y_train: pd.Series) -> Pipeline:
    """Train a sklearn pipeline.

    Args:
        pipeline: Sklearn pipeline to train
        X_train: Training features
        y_train: Training labels

    Returns:
        Trained pipeline
    """
    model_name = pipeline.steps[-1][1].__class__.__name__
    logger.info(f"Training {model_name}...")

    pipeline.fit(X_train, y_train)

    logger.success(f"{model_name} training completed")
    return pipeline


def train_and_evaluate(
    pipeline: Pipeline,
    X_train: pd.DataFrame,
    y_train: pd.Series,
    X_test: pd.DataFrame,
    y_test: pd.Series,
    evaluate_fn: EvaluateFn,
) -> tuple[Pipeline, dict, object, object]:
    """Train and evaluate a model pipeline.

    Args:
        pipeline: Sklearn pipeline to train
        X_train: Training features
        y_train: Training labels
        X_test: Test features
        y_test: Test labels
        evaluate_fn: Task-specific evaluator with signature
            `(trained_pipeline, X_test, y_test) -> (metrics, confusion_matrix, extra)`,
            e.g. a project's own `evaluate_model`

    Returns:
        Tuple of (trained_pipeline, metrics, confusion_matrix, extra)
    """
    trained_pipeline = train_model(pipeline, X_train, y_train)

    model_name = pipeline.steps[-1][1].__class__.__name__
    logger.info(f"Evaluating {model_name}...")

    metrics, cm, extra = evaluate_fn(trained_pipeline, X_test, y_test)
    logger.info(f"Metrics: {metrics}")

    return trained_pipeline, metrics, cm, extra
