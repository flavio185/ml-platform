#!/bin/bash
set -euo pipefail

echo "🚀 Setting up Argo Workflows"
echo "-----------------------------------"

# Argo Workflows controller (cluster-scoped)
kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.6.4/install.yaml

echo "Waiting for Argo Workflows controller..."
kubectl wait --for=condition=available deployment/argo-server -n argo --timeout=120s || true
kubectl wait --for=condition=available deployment/workflow-controller -n argo --timeout=120s || true

echo "🚀 Setting up Argo Events"
echo "-----------------------------------"

# Argo Events controller + EventBus
kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/examples/eventbus/native.yaml

echo "Waiting for Argo Events controller..."
kubectl wait --for=condition=available deployment/controller-manager -n argo-events --timeout=120s || true

# Apply RBAC for workflow execution across ml-* namespaces
echo "Applying RBAC..."
kubectl apply -f "$(dirname "$0")/rbac.yaml"

# Apply shared ClusterWorkflowTemplates
echo "Applying ClusterWorkflowTemplates..."
kubectl apply -f "$(dirname "$0")/cluster-workflow-templates.yaml"

echo "✅ Argo Workflows + Events setup complete"
