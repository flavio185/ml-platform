# Inference

Full inference stack for serverless model serving on AKS. Installs and configures all components
in dependency order. Fully generic: any project's `InferenceService`, in any namespace, gets its
inference payloads captured automatically — no per-project changes are needed to this directory.

## Architecture — path of a request

```
Client
  │  HTTP POST /v1/models/<model>:predict
  ▼
Istio IngressGateway (istio-system)
  │  routed by Host header to the project's Knative Route
  ▼
KServe InferenceService  (project namespace, e.g. ml-credit-default — any project)
  ├── predictor container   → runs the model, returns the prediction
  └── KServe agent sidecar  → intercepts request AND response, wraps each as a
                               CloudEvent (spec v1.0), HTTP POSTs both to logger.url
                                    │
                                    ▼
                    Knative Kafka Broker ingress (SHARED, cluster-wide)
                    http://kafka-broker-ingress.knative-eventing.svc.cluster.local
                                        /knative-serving/default
                                    │
                                    ▼
                         Kafka topic (knative-broker-knative-serving-default)
                                    │
                                    ▼
                    Trigger: payload-archiver-trigger (knative-serving)
                    filter: none — routes ALL events (request + response,
                    from every project's InferenceService)
                                    │
                                    ▼
                    payload-archiver consumer (inference-logging namespace)
                    — dedicated, generic, decoupled from any project or demo —
                    currently an echo-stub: logs each CloudEvent to stdout,
                    viewable via `kubectl logs -n inference-logging -l app=payload-archiver`
```

> **NEXT STEP (not built yet):** `payload-archiver` is deliberately just an echo-stub for now —
> it guarantees every inference payload lands *somewhere* and is inspectable. Replacing it with a
> durable sink (e.g. an Azure Blob Storage / data lake writer) is the next piece of work — see
> `PayloadArchiving/README.md`.

Everything above the Broker is already project-agnostic — confirmed working today with
`ml-default-payment-project`'s `default-payment-predictor` InferenceService in namespace
`ml-credit-default`, which simply points its `logger.url` at the same shared Broker. The Broker
itself needs no per-project configuration.

**Optional, per-project, not built by the platform:** a project that wants live CloudEvent-driven
drift detection or automated retraining defines its own `Trigger` (filtered by CloudEvent type,
subscriber pointing at its own consumer in its own namespace) inside its own `gitops/` — see
`KNativeEventing/README.md` → "Per-project triggers (optional)".

## Components

| Folder | Component | Required? | Version |
|--------|-----------|------------|---------|
| `CertManager/` | cert-manager (TLS certificate management) | Required | v1.20.1 |
| `Istio/` | Istio service mesh + IngressGateway | Required | v1.29.1 |
| `KNativeServing/` | Knative Serving + net-istio — scale-to-zero autoscaling, traffic routing | Required | v1.21.2 |
| `KServe/` | KServe model server (Serverless mode) | Required | v0.17.0 |
| `MetricsMonitoring/` | Prometheus `ServiceMonitor`s + Grafana dashboard for KServe/Knative metrics | Required | — |
| `KNativeEventing/` | Knative Eventing + Kafka Broker plugin — the shared event bus | Optional — only for CloudEvent-driven features | v1.21.2 |
| `PayloadArchiving/` | Generic consumer that captures every inference payload via the Broker | Optional — depends on `KNativeEventing/` | — |
| `Test/` | Optional smoke-test `InferenceService` manifests + end-to-end test script | Optional | — |

`KNativeServing/` and `KNativeEventing/` are independent Knative subprojects — Eventing has no
technical dependency on Serving (or Istio). They're installed together here purely because this
platform wants both, not because either requires the other. If you never need payload capture or
any other CloudEvent consumer, `KNativeEventing/`, `Kafka/` (one level up), and `PayloadArchiving/`
can all be skipped — `KNativeServing/` + `KServe/` alone is a complete, working serving stack.

Versions above are read from each component's `setup-*.sh` script (source of truth) — verify there directly if this table drifts again.

`GatewayAPI/` no longer exists (removed; `setup-kserve-stack.sh` has its invocation commented out rather than deleted, for reference).

## Installation order

Run the top-level orchestration script, which calls each component's setup script in the correct dependency order:

```bash
bash Inference/setup-kserve-stack.sh
```

This installs the full, generic platform stack — it does **not** deploy any demo namespace or
demo model. Any project's `InferenceService` pointed at the shared Broker URL (see architecture
above) is captured automatically once this finishes.

Manual step-by-step:

```bash
# Required — a complete, working serving stack on its own
bash Inference/CertManager/setup-certmanager.sh          # 1. cert-manager
bash Inference/Istio/setup-istio.sh                      # 2. Istio
bash Inference/KNativeServing/setup-knative-serving.sh    # 3. Knative Serving + net-istio
bash Inference/KServe/setup-kserve.sh                     # 4. KServe
bash Inference/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh  # 5. Metrics

# Optional — only needed for CloudEvent-driven features (currently: payload capture)
bash Kafka/setup-kafka.sh                                 # 6. Kafka (Strimzi)
bash Inference/KNativeEventing/setup-knative-eventing.sh  # 7. Knative Eventing + Kafka Broker plugin
bash Inference/PayloadArchiving/setup-payload-archiving.sh # 8. Payload archiving
```

## Testing the platform (optional)

The full stack above has no InferenceService of its own to test against. To validate the
pipeline end-to-end with a throwaway demo model (sklearn iris), run the separate, explicit,
manual steps documented in `Test/README.md` — this requires standing up the demo `app-ns`
namespace first (`bash app-ns/setup-app-ns.sh`), which is intentionally not a dependency of
`setup-kserve-stack.sh`.

## Dependencies

- AKS cluster running and `kubeconfig` configured (`AKS/aks_cluster_manager.sh getcreds`)
- `kube-prometheus-stack` installed (`Observability/setup-monitoring.sh`) — required before step 5

## Notes

- After installing Knative Serving (step 3), if KServe was already running, restart it so it detects Knative: `kubectl rollout restart deployment/kserve-controller-manager -n kserve`
- The Knative `kafka-broker-dispatcher` pod may trigger cluster autoscaler scale-up on first deploy — `setup-payload-archiving.sh` waits up to 300s for the Trigger to become Ready
