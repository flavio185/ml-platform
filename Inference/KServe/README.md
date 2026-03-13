# KServe

Installs KServe v0.15.2 in Serverless mode on AKS.

## Contents

| File | Purpose |
|------|---------|
| `setup-kserve.sh` | Installs KServe CRDs and controller via Helm, then applies `configmap.yaml` |
| `configmap.yaml` | KServe `inferenceservice-config` — storage initializer and serving runtime settings |

## Install

```bash
bash Inference/KServe/setup-kserve.sh
```

Installs into the `kserve` namespace and waits for the webhook server to be ready before applying cluster-scoped resources.

> If Knative Serving was installed after KServe, restart the controller so it detects it:
> ```bash
> kubectl rollout restart deployment/kserve-controller-manager -n kserve
> ```

## Inference payload logging

KServe's agent sidecar intercepts every request and response, emitting them as [CloudEvents](https://cloudevents.io/) (spec v1.0) via HTTP POST to a configured `logger.url`.

### Implemented architecture

```
Client
  │
  ▼
Istio IngressGateway
  │
  ▼
KServe InferenceService (app-ns)
  ├── predictor container  →  model prediction
  └── agent sidecar        →  emits CloudEvents
                                    │
                    ┌───────────────▼───────────────┐
                    │  Knative Kafka Broker ingress  │
                    │  (knative-eventing namespace)  │
                    └───────────────┬───────────────┘
                                    │
               ┌────────────────────┼────────────────────┐
               ▼                    ▼                     ▼
       payload-archiver      drift-detector       retraining-trigger
       (all events)          (request only)       (drift.detected only)
```

### CloudEvent types emitted

| Type | Trigger |
|------|---------|
| `org.kubeflow.serving.inference.request` | Every inbound inference request |
| `org.kubeflow.serving.inference.response` | Every outbound model response |

### Logger URL (set in InferenceService spec)

```
http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-serving/default
```

See `Inference/KNative/PayloadLogging/` for the consumer services and `Inference/Test/sklearn-iris.yaml` for an example `InferenceService` with logging configured.

## Dependencies

- cert-manager (`Inference/CertManager/setup-certmanager.sh`)
- Istio (`Inference/Istio/setup-istio.sh`)
- Knative Serving + Eventing (`Inference/KNative/setup-knative.sh`)
