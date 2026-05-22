# Shared base image for all ML projects on the platform.
# Rebuilt infrequently — only when shared dependencies change.
# Per-project images extend this with: FROM ghcr.io/datamaster2026/ml-platform-base:latest
FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "feast[redis]>=0.41" \
    "mlflow[extras]>=3.1.1" \
    "ray[default]>=2.46.0" \
    "pandas>=2.0" \
    "scikit-learn>=1.5" \
    "great-expectations>=1.5.8" \
    "s3fs>=2025.7.0" \
    "boto3" \
    "pyarrow" \
    "loguru" \
    "typer"

WORKDIR /app
