#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kuberay"

# Update helm repo
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ 2>/dev/null || true
helm repo update kuberay

# Install KubeRay Operator with Prometheus ServiceMonitor enabled
helm upgrade --install kuberay-operator kuberay/kuberay-operator --version 1.4.2 \
  -n "$NAMESPACE" --create-namespace \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.serviceMonitor.selector.release=prometheus \
  --wait --timeout 5m

# Install KubeRay APIServer
helm upgrade --install kuberay-apiserver kuberay/kuberay-apiserver --version 1.4.0 \
  -n "$NAMESPACE" \
  --wait --timeout 5m

echo "✅ Ray (KubeRay) setup complete"
echo "  Operator namespace: $NAMESPACE"

# Save logs:
# https://docs.ray.io/en/latest/cluster/kubernetes/user-guides/persist-kuberay-custom-resource-logs.html
