# Inference

Full inference stack for serverless model serving on AKS. Installs and configures all components in dependency order.

## Architecture

```
Internet → Istio IngressGateway → KServe InferenceService (Knative Serving)
                                          │
                                          └─ KServe logger sidecar
                                                    │
                                          Knative Kafka Broker (knative-eventing)
                                                    │
                                    ┌───────────────┼───────────────┐
                              payload-archiver  drift-detector  retraining-trigger
```

## Components

| Folder | Component | Version |
|--------|-----------|---------|
| `GatewayAPI/` | Kubernetes Gateway API CRDs | v1.2.1 |
| `CertManager/` | cert-manager (TLS certificate management) | v1.16.1 |
| `Istio/` | Istio service mesh + IngressGateway | v1.26 |
| `KNative/` | Knative Serving + net-istio + Knative Eventing + Kafka Broker plugin | v1.14.1 |
| `KServe/` | KServe model server (Serverless mode) | v0.15.2 |
| `MetricsMonitoring/` | Prometheus `ServiceMonitor` for KServe metrics | — |
| `Test/` | `InferenceService` manifests + end-to-end test script | — |

## Installation order

Run the top-level orchestration script, which calls each component's setup script in the correct dependency order:

```bash
bash Inference/setup-kserve-stack.sh
```

Manual step-by-step:

```bash
bash Inference/GatewayAPI/setup-gatewayapi.sh      # 1. Gateway API CRDs
bash Inference/CertManager/setup-certmanager.sh    # 2. cert-manager
bash Inference/Istio/setup-istio.sh                # 3. Istio
bash Kafka/setup-kafka.sh                          # 4. Kafka (Strimzi)
bash Inference/KNative/setup-knative.sh            # 5. Knative Serving + Eventing + Kafka Broker
bash Inference/KServe/setup-kserve.sh              # 6. KServe
bash Inference/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh  # 7. Metrics
bash Inference/KNative/PayloadLogging/setup-payload-logging.sh           # 8. Payload logging
```

## Dependencies

- AKS cluster running and `kubeconfig` configured (`AKS/aks_cluster_manager.sh getcreds`)
- `app-ns` namespace created (`app-ns/setup-app-ns.sh`)
- `kube-prometheus-stack` installed (`Observability/setup-monitoring.sh`) — required before step 7

## Notes

- After installing Knative Serving (step 5), if KServe was already running, restart it so it detects Knative: `kubectl rollout restart deployment/kserve-controller-manager -n kserve`
- The Knative `kafka-broker-dispatcher` pod may trigger cluster autoscaler scale-up on first deploy — `setup-payload-logging.sh` waits up to 300s for Triggers to become Ready
