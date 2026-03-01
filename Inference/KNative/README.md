# KNative

Installs Knative Serving (with net-istio) and Knative Eventing (with the Kafka Broker plugin). Both are required for KServe Serverless mode.

## Version

Knative Serving, Eventing, net-istio, and Kafka Broker plugin: **v1.14.1**

## Contents

| File | Purpose |
|------|---------|
| `setup-knative.sh` | Installs Knative Serving + net-istio + Knative Eventing + Kafka Broker plugin |
| `kafka-broker-config.yaml` | `ConfigMap` + `Secret` — Kafka bootstrap address and auth |
| `broker.yaml` | Knative `Broker` (class: Kafka) in `knative-serving` namespace |
| `trigger.yaml` | `Trigger` resources routing CloudEvents to consumer services |
| `message-dumper.yaml` | Debug sink that echoes CloudEvents to stdout |
| `knative-serving.yaml` | Reference `KnativeServing` CR (Knative Operator format — not used by setup-knative.sh) |
| `PayloadLogging/` | Consumer deployments and end-to-end payload logging setup script |

## What setup-knative.sh installs

| Step | Component | Details |
|------|-----------|---------|
| 2 | Knative Serving CRDs | `serving-crds.yaml` |
| 3 | Knative Serving core | `serving-core.yaml` — controller, webhook, activator |
| 4 | net-istio | Istio ingress for Knative; patches `config-network` and `config-domain` |
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

Events flow: **KServe logger sidecar → Kafka Broker ingress → Kafka topic → Triggers → Consumer services**

### Broker ingress URL

```
http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-serving/default
```

This URL is set as `logger.url` in each `InferenceService`.

### Triggers

| Trigger | Filter | Sink |
|---------|--------|------|
| `payload-archiver-trigger` | All events | `payload-archiver` |
| `drift-detector-trigger` | `inference.request` only | `drift-detector` |
| `retraining-trigger` | `mlops.drift.detected` | `retraining-trigger` |

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
