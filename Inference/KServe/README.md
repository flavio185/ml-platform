# KServe

Installs KServe v0.17.0 in Serverless mode on AKS.

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
KServe InferenceService (per-project namespace, e.g. ml-credit-default — any project)
  ├── predictor container  →  model prediction
  └── agent sidecar        →  emits CloudEvents
                                    │
                    ┌───────────────▼───────────────┐
                    │  Knative Kafka Broker ingress  │
                    │  (knative-eventing namespace,  │
                    │       SHARED, generic)         │
                    └───────────────┬───────────────┘
                                    │
                                    ▼
                       payload-archiver (all events)
                       inference-logging namespace
                       — generic, decoupled, echo-stub for now —
```

> **NEXT STEP:** `payload-archiver` is an echo-stub — captures every payload for inspection via
> `kubectl logs`, but doesn't persist it durably yet. See
> `../KNative/PayloadLogging/README.md`.

Optional, per-project: a project wanting live CloudEvent-driven drift detection or retraining
defines its own `Trigger` + consumer — see `../KNative/README.md` → "Per-project triggers
(optional)". `ml-default-payment-project` instead uses a simpler pattern (an offline pipeline
step calling an Argo Events webhook directly), which is the recommended default.

### CloudEvent types emitted

| Type | Trigger |
|------|---------|
| `org.kubeflow.serving.inference.request` | Every inbound inference request |
| `org.kubeflow.serving.inference.response` | Every outbound model response |

### Logger URL (set in InferenceService spec)

```
http://kafka-broker-ingress.knative-eventing.svc.cluster.local/knative-serving/default
```

See `Inference/KNative/PayloadLogging/` for the archiver consumer and `ml-default-payment-project/gitops/kserve-inference.yaml` for a real, working `InferenceService` with logging configured (`Inference/Test/sklearn-iris.yaml` is an optional demo/smoke-test alternative — see `Inference/Test/README.md`).

## Dependencies

- cert-manager (`Inference/CertManager/setup-certmanager.sh`)
- Istio (`Inference/Istio/setup-istio.sh`)
- Knative Serving + Eventing (`Inference/KNative/setup-knative.sh`)
