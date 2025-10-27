helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki with single replica mode
# helm install loki grafana/loki --version 6.21.0 -f https://raw.githubusercontent.com/grafana/loki/refs/heads/main/production/helm/loki/single-binary-values.yaml --namespace observability-ns --create-namespace


# Loki
helm install loki grafana/loki-stack -n observability-ns \
  --set grafana.enabled=false \
  --set promtail.enabled=false