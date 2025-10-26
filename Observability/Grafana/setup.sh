helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana --version 8.6.2 -f Observability/Grafana/datasource-config.yaml --namespace observability-ns --create-namespace