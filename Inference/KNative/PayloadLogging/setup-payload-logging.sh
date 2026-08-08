#!/usr/bin/env bash
# File: setup-payload-logging.sh
# Purpose: Apply all KServe payload logging resources in strict dependency order
# Dependencies: setup-knative.sh must have run; Kafka cluster reachable at configured bootstrap address;
#               KServe installed and functional; kubectl configured for target AKS cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNATIVE_NS="knative-serving"
NAMESPACE="app-ns"

# ---------------------------------------------------------------------------
# Step 2: Ensure namespace default exists
# ---------------------------------------------------------------------------
echo ""
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "Namespace '${NAMESPACE}' already exists."
else
  echo "Creating namespace '${NAMESPACE}' ..."
  kubectl create namespace "${NAMESPACE}" \
    || { echo "ERROR: Step 2 failed — could not create namespace '${NAMESPACE}'. Aborting."; exit 1; }
fi

# ---------------------------------------------------------------------------
# Step 3: Apply Kafka broker config (Secret + ConfigMap + KafkaBrokerConfig)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3] Applying kafka-broker-config.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/../kafka-broker-config.yaml" \
  || { echo "ERROR: Step 3 failed — kafka-broker-config.yaml. Aborting."; exit 1; }

echo "Waiting for KafkaBrokerConfig 'kafka-broker-config' to be Ready (60s) ..."
kubectl wait --for=condition=Ready kafkabrokerconfiguration/kafka-broker-config \
  -n "${KNATIVE_NS}" \
  --timeout=60s \
  || echo "WARN: KafkaBrokerConfig readiness check skipped (CRD may not expose condition=Ready). Proceeding."

# ---------------------------------------------------------------------------
# Step 4: Apply Broker and wait for Kafka connectivity
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 4] Applying broker.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/../broker.yaml" \
  || { echo "ERROR: Step 4 failed — broker.yaml. Aborting."; exit 1; }

echo "Waiting for Broker 'default' to be Ready (90s timeout) ..."
kubectl wait --for=condition=Ready broker/default \
  -n "${KNATIVE_NS}" \
  --timeout=90s \
  || { echo "Broker not Ready. Check Kafka connectivity."; exit 1; }

# ---------------------------------------------------------------------------
# Step 5: Apply consumer Deployments + Services
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 5] Applying consumers.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/consumers.yaml" -n ${NAMESPACE} \
  || { echo "ERROR: Step 5 failed — consumers.yaml. Aborting."; exit 1; }

for consumer in payload-archiver drift-detector retraining-trigger; do
  echo "  Waiting for deployment/${consumer} in ${NAMESPACE} ..."
  kubectl rollout status deployment/"${consumer}" -n "${NAMESPACE}" --timeout=60s \
    || { echo "ERROR: Step 5 failed — ${consumer} rollout timed out. Aborting."; exit 1; }
done

# ---------------------------------------------------------------------------
# Step 6: Apply Triggers
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 6] Applying trigger.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/../trigger.yaml" \
  || { echo "ERROR: Step 6 failed — trigger.yaml. Aborting."; exit 1; }

echo "Waiting for all Triggers to be Ready in ${KNATIVE_NS} (300s timeout — may need to scale a node) ..."
kubectl wait --for=condition=Ready trigger --all \
  -n "${KNATIVE_NS}" \
  --timeout=300s \
  || { echo "ERROR: Step 6 failed — one or more Triggers not Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 7: Apply InferenceService
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 7] Applying sklearn-iris InferenceService ..."
kubectl apply -f "${SCRIPT_DIR}/../../Test/sklearn-iris.yaml" \
  || { echo "ERROR: Step 7 failed — sklearn-iris.yaml. Aborting."; exit 1; }

echo "Waiting for InferenceService 'sklearn-iris' to be Ready (300s timeout) ..."
kubectl wait --for=condition=Ready inferenceservice/sklearn-iris \
  -n "${NAMESPACE}" \
  --timeout=300s \
  || { echo "ERROR: Step 7 failed — sklearn-iris InferenceService not Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Final status
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "Payload logging pipeline deployed successfully. Final status:"
echo ""
echo "Brokers in ${KNATIVE_NS}:"
kubectl get broker -n "${KNATIVE_NS}"
echo ""
echo "Triggers in ${KNATIVE_NS}:"
kubectl get trigger -n "${KNATIVE_NS}"
echo ""
echo "InferenceServices in ${NAMESPACE}:"
kubectl get inferenceservice -n "${NAMESPACE}"
echo "════════════════════════════════════════════════════════════════════════"
