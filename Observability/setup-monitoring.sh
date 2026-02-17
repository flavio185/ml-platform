#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"
APP_NAMESPACE="app-ns"
RELEASE_NAME="kube-prometheus-stack"
VALUES_FILE="$SCRIPT_DIR/kube-prometheus-stack-values.yaml"

echo "-----------------------------------"
echo "Setting up Prometheus + Grafana"
echo "-----------------------------------"

# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Remove stale monitoring CRDs to avoid field-manager conflicts with Helm
# (safe on fresh setup; on re-runs Helm will recreate them)
kubectl get crds -o name 2>/dev/null | grep monitoring.coreos.com | xargs -r kubectl delete 2>/dev/null || true

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  -n "$NAMESPACE" --create-namespace \
  -f "$VALUES_FILE" \
  --wait --timeout 10m

echo "-----------------------------------"
echo "Setting up Loki (log aggregation)"
echo "-----------------------------------"

# Install Loki (log backend — no bundled Grafana or Promtail, we use Fluent Bit instead)
helm upgrade --install loki grafana/loki-stack \
  -n "$NAMESPACE" \
  --set grafana.enabled=false \
  --set promtail.enabled=false \
  --wait --timeout 5m

# Print Grafana access info
echo "Waiting for Grafana LoadBalancer IP..."
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
  svc/"$RELEASE_NAME"-grafana -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

GRAFANA_IP=$(kubectl get svc "$RELEASE_NAME"-grafana -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -n "$GRAFANA_IP" ]; then
  echo "Grafana: http://$GRAFANA_IP (admin / admin)"
else
  echo "Grafana external IP not yet available. Check with:"
  echo "  kubectl get svc $RELEASE_NAME-grafana -n $NAMESPACE"
fi
