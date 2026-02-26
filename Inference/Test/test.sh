#!/usr/bin/env bash
# File: test.sh
# Purpose: Send inference requests and verify CloudEvents flow through Kafka to consumer services
# Dependencies: sklearn-iris InferenceService Ready in namespace app-ns;
#               consumer Deployments running (payload-archiver, drift-detector, retraining-trigger);
#               Knative Broker + Triggers configured; jq installed

set -euo pipefail

NAMESPACE="app-ns"
INFERENCE_SERVICE="sklearn-iris"
INPUT='{"instances": [[6.8, 2.8, 4.8, 1.4]]}'

# ---------------------------------------------------------------------------
# Step 1: Resolve Istio IngressGateway + InferenceService hostname
# ---------------------------------------------------------------------------
# The Knative URL (e.g. http://sklearn-iris.app-ns.example.com) does not
# resolve in external DNS. Requests must go through the Istio IngressGateway
# IP with a Host header, which is how Knative/Istio routes traffic internally.
INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_PORT=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
SERVICE_HOSTNAME=$(kubectl get inferenceservice "${INFERENCE_SERVICE}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.status.url}' | cut -d'/' -f3)

if [[ -z "${INGRESS_HOST}" || -z "${SERVICE_HOSTNAME}" ]]; then
  echo "ERROR: Could not resolve IngressGateway IP or InferenceService hostname."
  echo "       Verify the service is Ready: kubectl get inferenceservice -n ${NAMESPACE}"
  exit 1
fi

PREDICT_URL="http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/${INFERENCE_SERVICE}:predict"
echo "Ingress:  ${INGRESS_HOST}:${INGRESS_PORT}"
echo "Hostname: ${SERVICE_HOSTNAME}"
echo "Endpoint: ${PREDICT_URL}"

# ---------------------------------------------------------------------------
# Step 2: Send 3 inference POST requests
# ---------------------------------------------------------------------------
echo ""
echo ">>> Sending 3 inference requests ..."
for i in 1 2 3; do
  echo ""
  echo "  --- Request ${i} ---"
  curl -s -X POST "${PREDICT_URL}" \
    -H "Host: ${SERVICE_HOSTNAME}" \
    -H "Content-Type: application/json" \
    -d "${INPUT}" | jq .
done

# ---------------------------------------------------------------------------
# Step 3: Allow events to propagate through Kafka
# ---------------------------------------------------------------------------
echo ""
echo ">>> Sleeping 5s to allow CloudEvents to propagate through Kafka ..."
sleep 5

# ---------------------------------------------------------------------------
# Step 4: Check payload-archiver logs (should show request + response events)
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo ">>> Logs from payload-archiver (last 30 lines) ..."
echo "════════════════════════════════════════════════════════════════════════"
kubectl logs -l app=payload-archiver -n "${NAMESPACE}" --tail=30

# ---------------------------------------------------------------------------
# Step 5: Check drift-detector logs (should show request events only)
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo ">>> Logs from drift-detector (last 30 lines) ..."
echo "════════════════════════════════════════════════════════════════════════"
kubectl logs -l app=drift-detector -n "${NAMESPACE}" --tail=30

# ---------------------------------------------------------------------------
# Step 6: Check retraining-trigger logs (should be empty unless drift emitted)
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo ">>> Logs from retraining-trigger (last 30 lines) ..."
echo "════════════════════════════════════════════════════════════════════════"
kubectl logs -l app=retraining-trigger -n "${NAMESPACE}" --tail=30

# ---------------------------------------------------------------------------
# Step 7: kn CLI reference commands
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "kn CLI reference commands to inspect the setup:"
echo ""
echo "  kn broker list -n knative-serving"
echo "  kn trigger list -n knative-serving"
echo "  kn trigger describe payload-archiver-trigger -n knative-serving"
echo "════════════════════════════════════════════════════════════════════════"
