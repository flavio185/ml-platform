#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/AKS/aks_cluster_manager.sh" createaks
sleep 30
# Get AKS credentials
bash "$SCRIPT_DIR/AKS/aks_cluster_manager.sh" getcreds
export KUBECONFIG=$HOME/.kube/config

# Create AWS credentials secret in the app namespace
# get aws credentials from .env file
source "$SCRIPT_DIR/.env"

bash "$SCRIPT_DIR/app-ns/setup-app-ns.sh"

# Setup Monitoring (Prometheus + Grafana)
echo "🚀 Setting up Monitoring"
echo "-----------------------------------"
bash "$SCRIPT_DIR/Observability/setup-monitoring.sh"

sleep 5
# Setup Ray
echo "🚀 Setting up Ray"
echo "-----------------------------------"
bash "$SCRIPT_DIR/Ray/setup-ray.sh"
sleep 30

# Setup MLFlow
echo "🚀 Setting up MLFlow"
echo "-----------------------------------"
helm upgrade --install mlflow "$SCRIPT_DIR/MLFlow/mlflow-chart" -n mlflow-ns --create-namespace
sleep 30

# Setup KServe
bash "$SCRIPT_DIR/Inference/setup-kserve-stack.sh"
sleep 30

# Setup Feast (Redis online store + registry DB + feature server)
echo "🚀 Setting up Feast"
echo "-----------------------------------"
bash "$SCRIPT_DIR/Feast/setup-feast.sh"
sleep 10

# Setup Argo Workflows + Argo Events
echo "🚀 Setting up Argo Workflows"
echo "-----------------------------------"
bash "$SCRIPT_DIR/ArgoWorkflows/setup-argo-workflows.sh"
sleep 10

# Setup Argo CD
echo "🚀 Setting up Argo CD"
echo "-----------------------------------"
bash "$SCRIPT_DIR/ArgoCD/setup-argocd.sh"
