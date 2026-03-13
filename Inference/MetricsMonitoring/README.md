# KServe Metrics Monitoring

Adds a Prometheus `ServiceMonitor` for KServe inference services.
This relies on the **kube-prometheus-stack** already deployed by `Observability/setup-monitoring.sh` — no separate Prometheus Operator is installed.

## How it works

The `ServiceMonitor` is created in the `monitoring` namespace with the label
`release: kube-prometheus-stack`, so the existing Prometheus instance picks it up
automatically. It watches **all namespaces** for Knative private services
(`networking.internal.knative.dev/serviceType: Private`) and scrapes the
`http-usermetric` port every 15 seconds.

## Install

```shell
Inference/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh
```

## Useful Prometheus queries

Request count over the last 60 seconds:
```
sum(increase(revision_app_request_latencies_count{service_name=~"<model>-predictor-default"}[60s]))
```

Mean latency over the last 60 seconds:
```
sum(increase(revision_app_request_latencies_sum{service_name=~"<model>-predictor-default"}[60s])) /
sum(increase(revision_app_request_latencies_count{service_name=~"<model>-predictor-default"}[60s]))
```

## Grafana Dashboard

A pre-built Grafana dashboard is deployed automatically by the setup script as a Kubernetes ConfigMap (`kserve-dashboard-configmap.yaml`).
The `kube-prometheus-stack` Grafana sidecar watches ConfigMaps labeled `grafana_dashboard: "1"` in the `monitoring` namespace and hot-loads them — no manual UI import needed.

### Accessing the dashboard

```shell
# Get the Grafana service address
kubectl get svc kube-prometheus-stack-grafana -n monitoring

# Open in browser: http://<EXTERNAL-IP>
# Navigate to: Dashboards → KServe Inference Services
```

### Dashboard panels

| Row | Panel | Query |
|---|---|---|
| Traffic | Request Rate (req/s) | `sum by (service_name) (rate(revision_app_request_latencies_count{service_name=~"$service"}[1m]))` |
| Traffic | Total Requests (5m stat) | `sum(increase(revision_app_request_latencies_count{service_name=~"$service"}[5m]))` |
| Latency | Mean Latency | `rate(…_sum[1m]) / rate(…_count[1m])` |
| Latency | P99 Latency | `histogram_quantile(0.99, sum by (service_name, le) (rate(revision_app_request_latencies_bucket{service_name=~"$service"}[5m])))` |
| Latency | P50 Latency | `histogram_quantile(0.50, …)` |
| Autoscaler | Desired vs Actual Pods | `autoscaler_desired_pods`, `autoscaler_actual_pods` |
| Autoscaler | Active Concurrency | `revision_app_request_concurrencies` |

A `$service` template variable (multi-select dropdown) lets you filter by model — values are populated from `label_values(revision_app_request_latencies_count, service_name)`.

## Removal

```shell
kubectl delete -f Inference/MetricsMonitoring/kserve-service-monitor.yaml
kubectl delete -f Inference/MetricsMonitoring/kserve-dashboard-configmap.yaml
```
