# KNativeEventing

Installs Knative Eventing (with the Kafka Broker plugin). **Optional** — core KServe model
serving works with `../KNativeServing/` alone. This is only needed to support CloudEvent-driven
features; today that means exactly one thing: `../PayloadArchiving/`. If you don't need inference
payload capture (or any other CloudEvent consumer), you can skip this directory and
`Kafka/setup-kafka.sh` entirely.

## Version

Knative Eventing, Kafka Broker plugin: **v1.21.2** (`setup-knative-eventing.sh`'s
`KNATIVE_VERSION`/`KAFKA_BROKER_VERSION`).

## Contents

| File | Purpose |
|------|---------|
| `setup-knative-eventing.sh` | Installs Knative Eventing CRDs + core + Kafka Broker plugin (controller + data-plane) |
| `kafka-broker-config.yaml` | `ConfigMap` + `Secret` — Kafka bootstrap address and auth |
| `broker.yaml` | Knative `Broker` (class: Kafka) in `knative-serving` namespace — the shared event bus every project's `InferenceService` logger and every Trigger (including per-project ones) attaches to |
| `reference/message-dumper.yaml` | Debug sink that echoes CloudEvents to stdout (not wired to any Trigger — apply manually for ad-hoc debugging) |

## What setup-knative-eventing.sh installs

| Step | Component | Details |
|------|-----------|---------|
| 1 | Knative Eventing CRDs | `eventing-crds.yaml` |
| 2 | Knative Eventing core | `eventing-core.yaml` — eventing-controller, eventing-webhook |
| 3a | Kafka Broker controller | `eventing-kafka-controller.yaml` |
| 3b | Kafka Broker data-plane | `eventing-kafka-broker.yaml` — kafka-broker-receiver, kafka-broker-dispatcher |

## Architecture

KServe emits two CloudEvent types for every inference call:

| Event type | Description |
|-----------|-------------|
| `org.kubeflow.serving.inference.request` | Inbound inference payload |
| `org.kubeflow.serving.inference.response` | Model prediction output |

Events flow: **KServe logger sidecar → Kafka Broker ingress → Kafka topic → Trigger → consumer**

### Broker ingress URL

```
http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-serving/default
```

This URL is set as `logger.url` in each `InferenceService`, in any project's namespace — the
Broker itself is shared and needs no per-project configuration.

### Per-project triggers (optional)

`broker.yaml` is the only shared Eventing primitive the platform installs here — it does not
install any Trigger itself (that's `../PayloadArchiving/trigger.yaml`, the platform's one
built-in consumer). A project that wants its own *live*, CloudEvent-driven processing (e.g.
per-request drift detection) defines its own `Trigger` for its own concerns. Two things to know:

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
  Trigger/consumer to run, and no Knative Eventing dependency needed at all if
  `../PayloadArchiving/` isn't wanted either. Only add a real per-project `Trigger` if you need
  per-request, event-driven processing of every inference call as it happens.

## Install

```bash
bash Inference/KNativeEventing/setup-knative-eventing.sh
```

Then set up the payload archiving pipeline (requires Kafka running first):

```bash
bash Inference/PayloadArchiving/setup-payload-archiving.sh
```

## Dependencies

- Kafka cluster running (`Kafka/setup-kafka.sh`) — required before `setup-payload-archiving.sh`

Note: this has no dependency on `../KNativeServing/` or Istio — Knative Eventing and Knative
Serving are independent subprojects. The two are installed together in
`setup-kserve-stack.sh` purely because this platform happens to want both, not because either
requires the other.
