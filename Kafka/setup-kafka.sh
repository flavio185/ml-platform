#!/usr/bin/env bash
# File: setup-kafka.sh
# Purpose: Install Strimzi Operator and create a single-broker Kafka cluster in the kafka namespace
# Dependencies: kubectl configured and connected to the target AKS cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRIMZI_VERSION="0.51.0"
NAMESPACE="kafka"

echo "kubectl context: $(kubectl config current-context)"

# ---------------------------------------------------------------------------
# Step 1: Ensure namespace exists
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 1] Ensuring namespace '${NAMESPACE}' exists ..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Step 2: Install Strimzi Operator
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 2] Installing Strimzi Operator ${STRIMZI_VERSION} into '${NAMESPACE}' ..."
curl -sL "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${STRIMZI_VERSION}/strimzi-cluster-operator-${STRIMZI_VERSION}.yaml" \
  | sed "s/namespace: myproject/namespace: ${NAMESPACE}/g" \
  | kubectl apply -f - -n "${NAMESPACE}" \
  || { echo "ERROR: Failed to install Strimzi Operator. Aborting."; exit 1; }

echo "Waiting for Strimzi Cluster Operator to be ready (240s timeout) ..."
kubectl wait --for=condition=ready pod \
  -l name=strimzi-cluster-operator \
  -n "${NAMESPACE}" \
  --timeout=240s \
  || { echo "ERROR: Strimzi Operator did not become ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 3: Create Kafka cluster
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3] Creating Kafka cluster 'kafka-cluster' ..."
kubectl apply -f "${SCRIPT_DIR}/kafka-cluster.yaml" \
  || { echo "ERROR: Failed to apply kafka-cluster.yaml. Aborting."; exit 1; }

echo "Waiting for Kafka cluster to be Ready (300s timeout) ..."
kubectl wait kafka/kafka-cluster \
  --for=condition=Ready \
  --timeout=300s \
  -n "${NAMESPACE}" \
  || { echo "ERROR: Kafka cluster did not become Ready within 300s."; exit 1; }

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "Kafka cluster ready. Bootstrap service:"
echo "  kafka-cluster-kafka-bootstrap.${NAMESPACE}.svc.cluster.local:9092"
echo ""
kubectl get kafka -n "${NAMESPACE}"
echo "════════════════════════════════════════════════════════════════════════"
