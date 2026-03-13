# Test

End-to-end inference test resources. Deploys an `sklearn-iris` `InferenceService` and validates the full pipeline: HTTP prediction → Kafka CloudEvents → consumer services.

## Contents

| File | Purpose |
|------|---------|
| `sklearn-iris.yaml` | `InferenceService` for the sklearn iris model with Kafka payload logging enabled |
| `sklearn-iris-scale.yaml` | Variant with custom autoscaling annotations |
| `iris-input.json` | Sample iris input payload for manual `curl` testing |
| `test.sh` | End-to-end test script |

## InferenceService

- **Model**: sklearn iris classifier loaded from `gs://kfserving-examples/models/sklearn/1.0/model`
- **Namespace**: `app-ns`
- **Logger**: emits `inference.request` and `inference.response` CloudEvents to the Kafka Broker ingress

## Running the test

```bash
bash Inference/Test/test.sh
```

The script:
1. Resolves the Istio IngressGateway IP and InferenceService hostname
2. Sends 9 POST requests to `/v1/models/sklearn-iris:predict`
3. Waits 5 seconds for CloudEvents to propagate through Kafka
4. Prints logs from `payload-archiver`, `drift-detector`, and `retraining-trigger`

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

- `app-ns` namespace created (`app-ns/setup-app-ns.sh`)
- Full inference stack installed (`Inference/setup-kserve-stack.sh`)
- Payload logging pipeline deployed (`Inference/KNative/PayloadLogging/setup-payload-logging.sh`)
- `jq` installed locally
