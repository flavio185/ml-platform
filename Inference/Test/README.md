# Test

OPTIONAL end-to-end inference smoke test. Deploys a demo `sklearn-iris` `InferenceService` and
validates the full payload-logging pipeline: HTTP prediction → Kafka CloudEvents →
payload-archiver.

This is **not** part of the generic platform install (`Inference/setup-kserve-stack.sh` does not
deploy anything in this directory) — it exists purely to prove the pipeline works, using a
throwaway demo model instead of a real project's InferenceService.

## Contents

| File | Purpose |
|------|---------|
| `sklearn-iris.yaml` | Demo `InferenceService` for the sklearn iris model with Kafka payload logging enabled |
| `sklearn-iris-scale.yaml` | Variant with custom autoscaling annotations |
| `iris-input.json` | Sample iris input payload for manual `curl` testing |
| `test.sh` | End-to-end test script |

## InferenceService

- **Model**: sklearn iris classifier loaded from `gs://kfserving-examples/models/sklearn/1.0/model`
- **Namespace**: `app-ns` (demo namespace, unrelated to any real project's namespace)
- **Logger**: emits `inference.request` and `inference.response` CloudEvents to the shared Kafka Broker ingress

## Running the test

```bash
# 1. Create the demo namespace (not done automatically by Inference/setup-kserve-stack.sh)
bash app-ns/setup-app-ns.sh

# 2. Deploy the demo InferenceService
kubectl apply -f Inference/Test/sklearn-iris.yaml
kubectl wait --for=condition=Ready inferenceservice/sklearn-iris -n app-ns --timeout=300s

# 3. Run the smoke test
bash Inference/Test/test.sh
```

`test.sh`:
1. Resolves the Istio IngressGateway IP and InferenceService hostname
2. Sends 9 POST requests to `/v1/models/sklearn-iris:predict`
3. Waits 5 seconds for CloudEvents to propagate through Kafka
4. Prints logs from `payload-archiver` (in the `inference-logging` namespace)

## Manual request

```bash
INGRESS=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
HOST=$(kubectl get inferenceservice sklearn-iris -n app-ns -o jsonpath='{.status.url}' | cut -d'/' -f3)

curl -X POST "http://${INGRESS}/v1/models/sklearn-iris:predict" \
  -H "Host: ${HOST}" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[6.8, 2.8, 4.8, 1.4]]}'
```

Expected response:

```json
{"predictions": [1]}
```

## Dependencies

- Full inference stack installed (`Inference/setup-kserve-stack.sh`)
- `app-ns` namespace created — **explicit, manual step for this demo only**, not required by
  `Inference/setup-kserve-stack.sh` (`bash app-ns/setup-app-ns.sh`)
- `jq` installed locally
