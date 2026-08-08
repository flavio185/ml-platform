# Shared base image for all ML projects on the platform.
# Rebuilt infrequently — only when shared dependencies change.
# Per-project images extend this with: FROM docker.io/flavio185/ml-platform-base:latest
FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl && \
    rm -rf /var/lib/apt/lists/*

RUN uv pip install --system --no-cache \
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

# GitHub CLI — genuine OS-level tool (unlike promote-model's own logic, which
# is a project dependency each consuming project pins via pyproject.toml/
# uv.lock — see packages/mlops-promote — precisely so that changing it doesn't
# require a base-image rebuild).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
