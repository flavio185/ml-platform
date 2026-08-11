# KNative

Installs Knative Serving (with net-istio) and Knative Eventing (with the Kafka Broker plugin). Both are required for KServe Serverless mode.

## Version

Knative Serving and Eventing, Kafka Broker plugin: **v1.21.2** (`setup-knative.sh`'s `KNATIVE_VERSION`/`KAFKA_BROKER_VERSION`). net-istio: **v1.21.1** (`NET_ISTIO_VERSION` — releases independently, may lag one patch behind Serving).

## Contents

| File | Purpose |
|------|---------|
| `setup-knative.sh` | Installs Knative Serving + net-istio + Knative Eventing + Kafka Broker plugin |
| `kafka-broker-config.yaml` | `ConfigMap` + `Secret` — Kafka bootstrap address and auth |
| `broker.yaml` | Knative `Broker` (class: Kafka) in `knative-serving` namespace |
| `trigger.yaml` | `Trigger` routing all CloudEvents to the generic `payload-archiver` consumer |
| `message-dumper.yaml` | Debug sink that echoes CloudEvents to stdout |
| `knative-serving.yaml` | Reference `KnativeServing` CR (Knative Operator format — not used by setup-knative.sh) |
| `PayloadLogging/` | `payload-archiver` consumer + its dedicated `inference-logging` namespace + end-to-end setup script |

## What setup-knative.sh installs

| Step | Component | Details |
|------|-----------|---------|
| 2 | Knative Serving CRDs | `serving-crds.yaml` |
| 3 | Knative Serving core | `serving-core.yaml` — controller, webhook, activator |
| 4 | net-istio | Istio ingress for Knative; patches `config-network` and `config-domain` |
| 4b | Observability | Patches `config-observability`: `request-metrics-protocol` and `metrics-protocol` both set to `"prometheus"` — both default to `"none"`, and without this queue-proxy/autoscaler never expose Prometheus-format `/metrics` at all (see `../MetricsMonitoring/README.md`) |
| 5 | Knative Eventing CRDs | `eventing-crds.yaml` |
| 6 | Knative Eventing core | `eventing-core.yaml` — eventing-controller, eventing-webhook |
| 7a | Kafka Broker controller | `eventing-kafka-controller.yaml` |
| 7b | Kafka Broker data-plane | `eventing-kafka-broker.yaml` — kafka-broker-receiver, kafka-broker-dispatcher |

## Architecture

KServe emits two CloudEvent types for every inference call:

| Event type | Description |
|-----------|-------------|
| `org.kubeflow.serving.inference.request` | Inbound inference payload |
| `org.kubeflow.serving.inference.response` | Model prediction output |

Events flow: **KServe logger sidecar → Kafka Broker ingress → Kafka topic → Trigger → payload-archiver consumer**

### Broker ingress URL

```
http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-serving/default
```

This URL is set as `logger.url` in each `InferenceService`, in any project's namespace — the
Broker itself is shared and needs no per-project configuration.

### Triggers

| Trigger | Filter | Sink |
|---------|--------|------|
| `payload-archiver-trigger` | All events | `payload-archiver` (`inference-logging` namespace) — the only shared, platform-owned Trigger |

### Per-project triggers (optional)

The platform intentionally defines only the generic archiver Trigger above. A project that wants
*live*, CloudEvent-driven drift detection or retraining defines its own `Trigger` for its own
concerns. Two things to know:

- **Knative constraint:** a `Trigger` must live in the same namespace as the `Broker` it
  references (`knative-serving`), even though it's authored and GitOps-owned in the project's own
  `gitops/`, filtered by CloudEvent type, and points at a consumer Service in the project's own
  namespace.
- **The existing worked example doesn't actually need one.** `ml-default-payment-project` already
  implements drift detection and retraining, but via a simpler pattern that bypasses the
  Broker/Trigger path entirely: its `ml_classification/pipelines/drift_check.py` pipeline step
  runs offline (not as a live CloudEvent subscriber) and POSTs straight to the Argo Events
  webhook defined in `gitops/argo-events.yaml` (`EventSource` + `Sensor`, submits the project's
  `full-ml-pipeline` `Workflow`). This is the **recommended default** — simpler, no extra
  Trigger/consumer to run. Only add a real per-project `Trigger` if you need per-request,
  event-driven processing of every inference call as it happens.

## Install

```bash
bash Inference/KNative/setup-knative.sh
```

Then set up the payload logging pipeline (requires Kafka running first):

```bash
bash Inference/KNative/PayloadLogging/setup-payload-logging.sh
```

## Dependencies

- Istio installed (`Inference/Istio/setup-istio.sh`)
- Kafka cluster running (`Kafka/setup-kafka.sh`) — required before `setup-payload-logging.sh`
