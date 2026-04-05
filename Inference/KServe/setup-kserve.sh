#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

export KSERVE_VERSION=v0.15.2
deploymentMode="Serverless"

echo "Installing KServe CRDs..."
helm upgrade --install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
  --version "${KSERVE_VERSION}" --namespace kserve --create-namespace --wait

echo "Installing KServe controller..."
# Install without --wait: the chart tries to apply ClusterServingRuntimes via webhook
# before the controller pod is ready, causing a race condition that fails the install.
# We wait for the pod explicitly below before applying cluster resources.
helm upgrade --install kserve oci://ghcr.io/kserve/charts/kserve \
  --version "${KSERVE_VERSION}" --namespace kserve --create-namespace \
  --set-string kserve.controller.deploymentMode="${deploymentMode}" || true

# Wait for the controller pod to be running
echo "Waiting for KServe controller pod to be ready..."
kubectl wait --for=condition=ready pod \
  -l control-plane=kserve-controller-manager \
  -n kserve \
  --timeout=300s

# Wait for the webhook to actually be serving (not just the pod being Ready)
echo "Waiting for KServe webhook to become available..."
for i in $(seq 1 30); do
  if kubectl get validatingwebhookconfigurations 2>/dev/null | grep -q kserve; then
    # Try a dry-run to confirm the webhook is accepting requests
    if kubectl apply --dry-run=server -f - <<'EOF' >/dev/null 2>&1
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: webhook-test
  namespace: kserve
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "s3://test/model"
EOF
    then
      echo "Webhook is ready."
      break
    fi
  fi
  echo "  Waiting for webhook... ($i/30)"
  sleep 5
done

# Install built-in ClusterServingRuntimes (sklearn, xgboost, lgbm, pytorch, etc.)
echo "Applying KServe cluster resources..."
kubectl apply --server-side -f \
  "https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve-cluster-resources.yaml"

kubectl wait --for=condition=established --timeout=120s \
  crd/clusterservingruntimes.serving.kserve.io

# Configure KNative queue-proxy resource limits so pods pass namespace ResourceQuotas
echo "Configuring KNative queue-proxy resource limits..."
kubectl patch configmap config-deployment -n knative-serving --type merge -p '{
  "data": {
    "queue-sidecar-cpu-request": "25m",
    "queue-sidecar-memory-request": "50Mi",
    "queue-sidecar-cpu-limit": "200m",
    "queue-sidecar-memory-limit": "256Mi"
  }
}' 2>/dev/null || true

kubectl apply -f "${SCRIPT_DIR}/configmap.yaml"

echo "✅ KServe setup complete (mode: ${deploymentMode})"
