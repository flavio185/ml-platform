# Add repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus + Grafana
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability-ns --create-namespace -f values.yaml

# Install Loki
helm install loki grafana/loki-stack \
  -n observability-ns -f values.yaml

# Install Fluent Bit
helm install fluent-bit grafana/fluent-bit \
  -n observability-ns -f values.yaml
