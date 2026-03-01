# Observability

Installs the observability stack: Prometheus, Grafana, Alertmanager, and Loki.

## Stack

| Component | Purpose | Installed via |
|-----------|---------|---------------|
| **Prometheus** | Metrics collection and alerting | `kube-prometheus-stack` Helm chart |
| **Grafana** | Dashboards and visualization | Bundled with `kube-prometheus-stack` |
| **Alertmanager** | Alert routing and notification | Bundled with `kube-prometheus-stack` |
| **Loki** | Log aggregation backend | `grafana/loki-stack` Helm chart |

> Fluent Bit (log shipper) is **not** deployed here — it runs as a sidecar in Ray pods, configured via `app-ns/fluentbit-config.yaml`.

## Install

```bash
bash Observability/setup-monitoring.sh
```

Installs into the `monitoring` namespace. Waits up to 10 minutes for `kube-prometheus-stack` and 5 minutes for Loki to become ready.

## Access Grafana

The script prints the Grafana external IP after install. Default credentials: `admin / admin`.

```bash
kubectl get svc kube-prometheus-stack-grafana -n monitoring
```

## Configuration

`kube-prometheus-stack-values.yaml` — Helm values for Prometheus and Grafana. Key settings:

- Grafana service type: `LoadBalancer` (exposes external IP on AKS)
- `serviceMonitorSelectorNilUsesHelmValues: false` — Prometheus picks up `ServiceMonitor` resources from any namespace (required for KServe metrics)

## KServe metrics integration

After installing the observability stack, enable KServe metric collection:

```bash
bash Inference/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh
```

This applies a `ServiceMonitor` in the `monitoring` namespace that scrapes Knative private service pods every 15 seconds.

## Log pipeline

```
Ray pod /tmp/ray logs → Fluent Bit sidecar → Loki (monitoring ns) → Grafana
```

Fluent Bit is configured in `app-ns/fluentbit-config.yaml` and mounts into Ray head and worker pods via the `RayJob` spec in `Ray/ray-model-training-job-monitoring.yaml`.
