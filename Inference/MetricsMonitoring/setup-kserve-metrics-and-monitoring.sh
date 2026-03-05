#!/usr/bin/env bash
set -euo pipefail

# Aplica o ServiceMonitor do KServe no Prometheus já existente (kube-prometheus-stack no namespace monitoring).
# Não instala um Prometheus Operator separado — reutiliza o stack de Observability.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Applying KServe ServiceMonitor to monitoring namespace..."
kubectl apply -f "${SCRIPT_DIR}/kserve-service-monitor.yaml"
echo "KServe ServiceMonitor applied successfully."

kubectl apply -f "${SCRIPT_DIR}/kserve-dashboard-configmap.yaml"
echo "KServe Grafana dashboard ConfigMap applied."
