# PayloadLogging

Deploys the generic, project-agnostic CloudEvent consumer that captures every KServe inference
payload — from any project's `InferenceService`, in any namespace — for later archiving.

## Contents

| File | Purpose |
|------|---------|
| `namespace.yaml` | Declarative `Namespace: inference-logging` — dedicated home for the consumer, decoupled from any project or demo namespace |
| `setup-payload-logging.sh` | Orchestrates the full deployment in strict dependency order |
| `consumers.yaml` | `payload-archiver` `Deployment` + `Service` in `inference-logging` |

## Consumer service

| Service | Event filter | Intended replacement |
|---------|-------------|---------------------|
| `payload-archiver` | All events (request + response), from every project | NEXT STEP (not built here): a service writing CloudEvent payloads to durable storage (e.g. Azure Blob Storage / data lake) |

> Currently a `mendhak/http-https-echo` stub — it echoes received CloudEvents to stdout, viewable
> via `kubectl logs`, so you can confirm payloads are being captured. This deliberately stops
> short of durable storage; that's the next piece of work.

Live, per-project CloudEvent consumers (e.g. drift detection, retraining) are **not** deployed
here — see `../README.md` → "Per-project triggers (optional)" for that pattern.

## Setup

```bash
bash Inference/KNative/PayloadLogging/setup-payload-logging.sh
```

Deployment steps (in order):

1. Apply `namespace.yaml` (creates `inference-logging`)
2. Apply `kafka-broker-config.yaml` (Kafka connection config)
3. Apply `broker.yaml` and wait for Broker `Ready`
4. Apply `consumers.yaml` and wait for the `payload-archiver` deployment
5. Apply `trigger.yaml` and wait for the Trigger `Ready` (up to 300s — `kafka-broker-dispatcher` may trigger cluster autoscaler scale-up)

No demo `InferenceService` is deployed by this script — see `../../Test/README.md` for the
optional iris smoke test.

## Verify

```bash
# Check Broker and Trigger
kn broker list -n knative-serving
kn trigger list -n knative-serving

# Check the consumer pod
kubectl get pods -n inference-logging -l app=payload-archiver

# Run the optional end-to-end smoke test (requires app-ns/setup-app-ns.sh run first
# and the sklearn-iris InferenceService applied manually — see ../../Test/README.md)
bash Inference/Test/test.sh
```

## Dependencies

- `setup-knative.sh` completed (Knative Eventing + Kafka Broker plugin installed)
- Kafka cluster reachable at the address in `../kafka-broker-config.yaml`
- KServe installed (`Inference/KServe/setup-kserve.sh`)
