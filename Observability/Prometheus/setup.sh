# Prometheus + Grafana → use the community chart:
# Includes Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics.
# Deploys CRDs ServiceMonitor and PodMonitor you can reuse for Ray and KServe.
# Grafana is pre-wired to Prometheus.

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability-ns \
  --create-namespace

