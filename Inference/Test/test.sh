#!/usr/bin/env bash
# File: test.sh
# Purpose: Send inference requests and verify CloudEvents flow through Kafka to consumer services
# Dependencies: sklearn-iris InferenceService Ready in namespace default;
#               consumer Deployments running (payload-archiver, drift-detector, retraining-trigger);
#               Knative Broker + Triggers configured; jq installed

set -euo pipefail

NAMESPACE="app-ns"
INFERENCE_SERVICE="sklearn-iris"
INPUT='{"instances": [[6.8, 2.8, 4.8, 1.4]]}'

# ---------------------------------------------------------------------------
# Step 1: Get InferenceService URL dynamically
# ---------------------------------------------------------------------------
echo ">>> Fetching InferenceService URL for '${INFERENCE_SERVICE}' in namespace '${NAMESPACE}' ..."
PREDICT_URL=$(kubectl get inferenceservice "${INFERENCE_SERVICE}" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.status.url}')

if [[ -z "${PREDICT_URL}" ]]; then
  echo "ERROR: Could not retrieve URL for InferenceService '${INFERENCE_SERVICE}'."
  echo "       Verify the service is Ready: kubectl get inferenceservice -n ${NAMESPACE}"
  exit 1
fi

PREDICT_URL="${PREDICT_URL}/v1/models/${INFERENCE_SERVICE}:predict"
echo "Prediction endpoint: ${PREDICT_URL}"

# ---------------------------------------------------------------------------
# Step 2: Send 3 inference POST requests
# ---------------------------------------------------------------------------
echo ""
echo ">>> Sending 3 inference requests ..."
for i in 1 2 3; do
  echo ""
  echo "  --- Request ${i} ---"
  curl -sf -X POST "${PREDICT_URL}" \
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
