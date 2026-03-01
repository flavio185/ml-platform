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

## Removal

```shell
kubectl delete -f Inference/MetricsMonitoring/kserve-service-monitor.yaml
```
