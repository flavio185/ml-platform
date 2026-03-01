# PayloadLogging

Deploys the CloudEvent consumer pipeline that captures KServe inference payloads for archiving, drift detection, and automated retraining.

## Contents

| File | Purpose |
|------|---------|
| `setup-payload-logging.sh` | Orchestrates the full deployment in strict dependency order |
| `consumers.yaml` | Three consumer `Deployment` + `Service` resources in `app-ns` |

## Consumer services

| Service | Event filter | Intended replacement |
|---------|-------------|---------------------|
| `payload-archiver` | All events (request + response) | Python service writing CloudEvent payloads to Azure Blob Storage |
| `drift-detector` | `inference.request` only | Evidently AI or custom PSI/KS drift detector; emits `mlops.drift.detected` when threshold exceeded |
| `retraining-trigger` | `mlops.drift.detected` | Argo Workflows EventSource + Sensor that submits a RayJob to retrain the model |

> Stubs currently use `mendhak/http-https-echo` to echo received CloudEvents to stdout for validation.

## Setup

```bash
bash Inference/KNative/PayloadLogging/setup-payload-logging.sh
```

Deployment steps (in order):

1. Ensure `app-ns` namespace exists
2. Apply `kafka-broker-config.yaml` (Kafka connection config)
3. Apply `broker.yaml` and wait for Broker `Ready`
4. Apply `consumers.yaml` and wait for all three deployments
5. Apply `trigger.yaml` and wait for all Triggers `Ready` (up to 300s — `kafka-broker-dispatcher` may trigger cluster autoscaler scale-up)
6. Deploy `sklearn-iris` `InferenceService` with Kafka logger URL

## Verify

```bash
# Check Broker and Triggers
kn broker list -n knative-serving
kn trigger list -n knative-serving

# Check consumer pods
kubectl get pods -n app-ns -l app=payload-archiver
kubectl get pods -n app-ns -l app=drift-detector
kubectl get pods -n app-ns -l app=retraining-trigger

# Run end-to-end test
bash Inference/Test/test.sh
```

## Dependencies

- `setup-knative.sh` completed (Knative Eventing + Kafka Broker plugin installed)
- Kafka cluster reachable at the address in `../kafka-broker-config.yaml`
- KServe installed (`Inference/KServe/setup-kserve.sh`)
- `app-ns` namespace created with AWS credentials (`app-ns/setup-app-ns.sh`)
