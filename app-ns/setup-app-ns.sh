#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="ml-credit-default"

# Validate required env vars are set (sourced from .env in parent setup.sh)
: "${AWS_ACCESS_KEY_ID:?ERROR: AWS_ACCESS_KEY_ID is not set. Source .env before running.}"
: "${AWS_SECRET_ACCESS_KEY:?ERROR: AWS_SECRET_ACCESS_KEY is not set. Source .env before running.}"
# Classic PAT with `repo` scope (or fine-grained: Contents + Pull requests: write)
# against the target project repo — used by the promote-model ClusterWorkflowTemplate
# (ArgoWorkflows/cluster-workflow-templates.yaml) to open/auto-merge promote/* PRs.
: "${GITHUB_TOKEN:?ERROR: GITHUB_TOKEN is not set. Source .env before running.}"

# Create namespace idempotently
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create AWS credentials secret (idempotent)
kubectl create secret generic aws-credentials \
  --namespace "$NAMESPACE" \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create GitHub credentials secret (idempotent) — key name (token) matches what
# the promote-model ClusterWorkflowTemplate reads via secretKeyRef.
kubectl create secret generic github-credentials \
  --namespace "$NAMESPACE" \
  --from-literal=token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -


kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite

# Apply all YAML manifests in this directory
for f in "$SCRIPT_DIR"/*.yaml; do
  echo "🚀 Applying $(basename "$f") in $NAMESPACE"
  kubectl apply -f "$f" -n "$NAMESPACE"
done
