#!/usr/bin/env bash
# File: setup-payload-logging.sh
# Purpose: Apply all KServe payload logging resources in strict dependency order
# Dependencies: setup-knative.sh must have run; Kafka cluster reachable at configured bootstrap address;
#               KServe installed and functional; kubectl configured for target AKS cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNATIVE_NS="knative-serving"
NAMESPACE="inference-logging"

# ---------------------------------------------------------------------------
# Step 1: Ensure namespace inference-logging exists
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 1] Applying namespace.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/namespace.yaml" \
  || { echo "ERROR: Step 1 failed — namespace.yaml. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 2: Apply Kafka broker config (Secret + ConfigMap + KafkaBrokerConfig)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 2] Applying kafka-broker-config.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/../kafka-broker-config.yaml" \
  || { echo "ERROR: Step 2 failed — kafka-broker-config.yaml. Aborting."; exit 1; }

echo "Waiting for KafkaBrokerConfig 'kafka-broker-config' to be Ready (60s) ..."
kubectl wait --for=condition=Ready kafkabrokerconfiguration/kafka-broker-config \
  -n "${KNATIVE_NS}" \
  --timeout=60s \
  || echo "WARN: KafkaBrokerConfig readiness check skipped (CRD may not expose condition=Ready). Proceeding."

# ---------------------------------------------------------------------------
# Step 3: Apply Broker and wait for Kafka connectivity
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3] Applying broker.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/../broker.yaml" \
  || { echo "ERROR: Step 3 failed — broker.yaml. Aborting."; exit 1; }

echo "Waiting for Broker 'default' to be Ready (90s timeout) ..."
kubectl wait --for=condition=Ready broker/default \
  -n "${KNATIVE_NS}" \
  --timeout=90s \
  || { echo "Broker not Ready. Check Kafka connectivity."; exit 1; }

# ---------------------------------------------------------------------------
# Step 4: Apply consumer Deployment + Service
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 4] Applying consumers.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/consumers.yaml" \
  || { echo "ERROR: Step 4 failed — consumers.yaml. Aborting."; exit 1; }

echo "  Waiting for deployment/payload-archiver in ${NAMESPACE} ..."
kubectl rollout status deployment/payload-archiver -n "${NAMESPACE}" --timeout=120s \
  || { echo "ERROR: Step 4 failed — payload-archiver rollout timed out. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 5: Apply Triggers
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 5] Applying trigger.yaml ..."
kubectl apply -f "${SCRIPT_DIR}/../trigger.yaml" \
  || { echo "ERROR: Step 5 failed — trigger.yaml. Aborting."; exit 1; }

echo "Waiting for all Triggers to be Ready in ${KNATIVE_NS} (300s timeout — may need to scale a node) ..."
kubectl wait --for=condition=Ready trigger --all \
  -n "${KNATIVE_NS}" \
  --timeout=300s \
  || { echo "ERROR: Step 5 failed — one or more Triggers not Ready. Aborting."; exit 1; }

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
echo "Consumers in ${NAMESPACE}:"
kubectl get pods -n "${NAMESPACE}" -l app=payload-archiver
echo ""
echo "No demo InferenceService is deployed by this script — any project's"
echo "InferenceService pointed at the shared Broker URL is already captured."
echo "To validate the pipeline end-to-end with the optional iris smoke test,"
echo "see ../../Test/README.md."
echo "════════════════════════════════════════════════════════════════════════"
