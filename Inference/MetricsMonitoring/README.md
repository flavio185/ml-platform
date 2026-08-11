# KServe Metrics Monitoring

Adds Prometheus `ServiceMonitor`s and a Grafana dashboard for KServe/Knative inference metrics.
This relies on the **kube-prometheus-stack** already deployed by `Observability/setup-monitoring.sh`
(namespace **`observability`**, not `monitoring`) — no separate Prometheus Operator is installed.

## Prerequisite: enable Prometheus-format metrics in Knative

By default, Knative's `request-metrics-protocol` and `metrics-protocol` (in the `config-observability`
ConfigMap, namespace `knative-serving`) are both `"none"` — queue-proxy and the autoscaler emit **no**
Prometheus-scrapeable data at all until these are set. `../KNativeServing/setup-knative-serving.sh`
patches both to `"prometheus"` as of step 4; if metrics show nothing anywhere downstream (Prometheus
targets down, Grafana panels empty), check this first:

```shell
kubectl get configmap config-observability -n knative-serving \
  -o jsonpath='{.data.request-metrics-protocol}{"\n"}{.data.metrics-protocol}{"\n"}'
# both must print "prometheus"
```

The Knative `autoscaler` Deployment only picks up a `config-observability` change on restart, not live:

```shell
kubectl rollout restart deployment/autoscaler -n knative-serving
```

## How it works

Two `ServiceMonitor`s, both labeled `release: kube-prometheus-stack` so the existing Prometheus
instance picks them up automatically:

| ServiceMonitor | Namespace | Selector | Port scraped | Source |
|---|---|---|---|---|
| `kserve-monitoring` | `observability` | Knative private services (`networking.internal.knative.dev/serviceType: Private`), all namespaces | `http-usermetric` (9091) | Per-InferenceService queue-proxy — request-level metrics |
| `knative-autoscaler-monitoring` | `knative-serving` | `app=autoscaler` | `http-metrics` (9090) | The cluster-wide Knative autoscaler singleton — desired/actual pod counts, concurrency |

Note: `http-autometric` (9090) on a **predictor's own** private service is a different, internal-only
OpenCensus/protobuf channel queue-proxy uses to talk to the autoscaler — it's not Prometheus-scrapeable
regardless of the above config, and is not what either ServiceMonitor targets.

## Install

```shell
Inference/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh
```

## Metric names (Knative 1.21+, OpenTelemetry-based)

Knative renamed its metrics with a `kn_` prefix when it moved to OpenTelemetry; older docs/dashboards
referencing `revision_app_request_*` or `autoscaler_*` are stale for this version.

| Source | Metric | Labels |
|---|---|---|
| queue-proxy (9091) | `kn_serving_invocation_duration_seconds_{bucket,count,sum}` | No per-revision label on the metric itself — use Prometheus's auto-injected `service`/`namespace`/`pod` labels from the ServiceMonitor scrape instead (`service` includes the revision suffix and a `-private` suffix, e.g. `<ksvc>-00002-private`) |
| autoscaler (9090) | `kn_revision_pods_count` (actual), `kn_revision_pods_desired`, `kn_revision_concurrency_stable`, `kn_revision_concurrency_panic` | `kn_service_name`, `kn_revision_name`, `kn_configuration_name`, `k8s_namespace_name` |

## Useful Prometheus queries

Request count over the last 60 seconds, for a given Knative Service (note the `-.*` — `service`
carries the revision + `-private` suffix, not the bare Service name):

```
sum(increase(kn_serving_invocation_duration_seconds_count{service=~"<model>-predictor-.*"}[60s]))
```

Mean latency over the last 60 seconds:

```
sum(increase(kn_serving_invocation_duration_seconds_sum{service=~"<model>-predictor-.*"}[60s])) /
sum(increase(kn_serving_invocation_duration_seconds_count{service=~"<model>-predictor-.*"}[60s]))
```

Desired vs. actual pods:

```
kn_revision_pods_desired{kn_service_name=~"<model>-predictor"}
kn_revision_pods_count{kn_service_name=~"<model>-predictor"}
```

## Grafana Dashboard

A pre-built Grafana dashboard is deployed automatically by the setup script as a Kubernetes ConfigMap
(`kserve-dashboard-configmap.yaml`). The `kube-prometheus-stack` Grafana sidecar watches ConfigMaps
labeled `grafana_dashboard: "1"` in the `observability` namespace and hot-loads them — no manual UI
import needed.

`kserve-dashboard-configmap.yaml` embeds a full copy of `kserve-dashboard.json`'s JSON inside a YAML
`data` block — they are **not** the same object at apply time. If you edit `kserve-dashboard.json`,
regenerate the ConfigMap from it (don't hand-edit the embedded copy) before applying:

```shell
python3 -c "
with open('kserve-dashboard.json') as f:
    dashboard_json = f.read()
header = '''apiVersion: v1
kind: ConfigMap
metadata:
  name: kserve-grafana-dashboard
  labels:
    grafana_dashboard: \"1\"
data:
  kserve-dashboard.json: |
'''
indented = '\n'.join('    ' + l if l.strip() else l for l in dashboard_json.splitlines())
open('kserve-dashboard-configmap.yaml', 'w').write(header + indented + '\n')
"
kubectl apply -f kserve-dashboard-configmap.yaml -n observability
```

### Accessing the dashboard

```shell
# Get the Grafana service address
kubectl get svc kube-prometheus-stack-grafana -n observability

# Open in browser: http://<EXTERNAL-IP>
# Navigate to: Dashboards → KServe Inference Services
```

### Dashboard panels

| Row | Panel | Query |
|---|---|---|
| Traffic | Request Rate (req/s) | `sum by (service) (rate(kn_serving_invocation_duration_seconds_count{service=~"${service}-.*", namespace=~"$namespace"}[1m]))` |
| Traffic | Total Requests (5m stat) | `sum(increase(kn_serving_invocation_duration_seconds_count{service=~"${service}-.*", namespace=~"$namespace"}[5m]))` |
| Latency | Mean Latency | `rate(..._sum[1m]) / rate(..._count[1m])`, same label filters |
| Latency | P99 Latency | `histogram_quantile(0.99, sum by (service, le) (rate(kn_serving_invocation_duration_seconds_bucket{service=~"${service}-.*", namespace=~"$namespace"}[5m])))` |
| Latency | P50 Latency | `histogram_quantile(0.50, ...)` |
| Autoscaler | Desired vs Actual Pods | `kn_revision_pods_desired{kn_service_name=~"$service", k8s_namespace_name=~"$namespace"}`, `kn_revision_pods_count{...}` |
| Autoscaler | Active Concurrency | `kn_revision_concurrency_stable{kn_service_name=~"$service", k8s_namespace_name=~"$namespace"}` |

Two chained template variables (both multi-select, "All" by default):

- **`$namespace`** — from `label_values(kn_revision_pods_count, k8s_namespace_name)`.
- **`$service`** — from `label_values(kn_revision_pods_count{k8s_namespace_name=~"$namespace"}, kn_service_name)`, so it narrows to only services actually running in the selected namespace(s).

## Removal

```shell
kubectl delete -f Inference/MetricsMonitoring/kserve-service-monitor.yaml
kubectl delete -f Inference/MetricsMonitoring/kserve-dashboard-configmap.yaml -n observability
```

(`kserve-service-monitor.yaml` contains two `ServiceMonitor`s in different namespaces —
`kubectl delete -f` handles that correctly since each object carries its own `metadata.namespace`;
don't add a blanket `-n` override to that command or it will only match the un-namespaced one.)
