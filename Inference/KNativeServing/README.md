# KNativeServing

Installs Knative Serving (with net-istio). **Required** for any KServe Serverless
`InferenceService` — this is what provides scale-to-zero autoscaling and routes traffic to
predictor pods. Every project needs this installed; nothing here is optional.

This does not include Knative Eventing — see `../KNativeEventing/` for that (only needed if you
want CloudEvent-driven features like payload archiving).

## Version

Knative Serving: **v1.21.2** (`setup-knative-serving.sh`'s `KNATIVE_VERSION`). net-istio:
**v1.21.1** (`NET_ISTIO_VERSION` — releases independently, may lag one patch behind Serving).

## Contents

| File | Purpose |
|------|---------|
| `setup-knative-serving.sh` | Installs Knative Serving CRDs + core + net-istio, patches Istio ingress/domain/observability config, self-heals a known autoscaler metrics-exporter startup race |
| `reference/knative-serving.yaml` | Reference `KnativeServing` CR (Knative Operator format — not used by setup-knative-serving.sh, kept for reference only) |

## What setup-knative-serving.sh installs

| Step | Component | Details |
|------|-----------|---------|
| 1 | Namespace | `knative-serving` |
| 2 | Knative Serving CRDs | `serving-crds.yaml` |
| 3 | Knative Serving core | `serving-core.yaml` — controller, webhook, activator, autoscaler |
| 4 | net-istio + config patches | Istio ingress for Knative; patches `config-network`, `config-domain`, and `config-observability` (`request-metrics-protocol`/`metrics-protocol` → `"prometheus"`, both default to `"none"` — without this queue-proxy/autoscaler never expose Prometheus-format `/metrics` at all, see `../MetricsMonitoring/README.md`); patches the autoscaler's `livenessProbe` to self-heal a known metrics-exporter startup race |

## Install

```bash
bash Inference/KNativeServing/setup-knative-serving.sh
```

## Dependencies

- Istio installed (`Inference/Istio/setup-istio.sh`)

## Notes

- After this installs, if KServe was already running, restart it so it detects Knative: `kubectl rollout restart deployment/kserve-controller-manager -n kserve`
