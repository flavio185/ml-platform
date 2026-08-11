#!/usr/bin/env bash
# File: setup-knative-eventing.sh
# Purpose: Install Knative Eventing + Kafka Broker plugin — OPTIONAL, only needed
#          to support event-driven features (currently: PayloadArchiving). Core
#          KServe model serving works with Knative Serving alone; skip this
#          script entirely if you don't need inference payload capture or any
#          other CloudEvent-driven consumer.
# Dependencies: kubectl configured and connected to the target AKS cluster;
#               Kafka cluster running (Kafka/setup-kafka.sh)

set -euo pipefail

KNATIVE_VERSION="v1.21.2"
KAFKA_BROKER_VERSION="v1.21.2"
SERVING_NAMESPACE="knative-serving"

# ---------------------------------------------------------------------------
# Step 1: Knative Eventing CRDs
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 1] Installing Knative Eventing CRDs (${KNATIVE_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-crds.yaml" \
  || { echo "ERROR: Failed to apply Knative Eventing CRDs. Aborting."; exit 1; }

echo "Waiting for Eventing CRDs to become Established (60s timeout) ..."
kubectl wait --for=condition=Established --timeout=60s \
  crd/brokers.eventing.knative.dev \
  crd/triggers.eventing.knative.dev \
  crd/eventtypes.eventing.knative.dev \
  || { echo "ERROR: Knative Eventing CRDs did not establish within 60s. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 2: Knative Eventing core
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 2] Installing Knative Eventing core (${KNATIVE_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml" \
  || { echo "ERROR: Failed to apply Knative Eventing core. Aborting."; exit 1; }

# Modern Eventing release manifests create their own knative-eventing namespace.
# Fall back to the Serving namespace only if that didn't happen (older versions
# installed Eventing components alongside Serving in one shared namespace).
EVENTING_NAMESPACE="knative-eventing"
if ! kubectl get namespace "${EVENTING_NAMESPACE}" &>/dev/null; then
  EVENTING_NAMESPACE="${SERVING_NAMESPACE}"
fi

echo "Waiting for eventing-controller in ${EVENTING_NAMESPACE} (300s timeout) ..."
kubectl rollout status deployment/eventing-controller \
  -n "${EVENTING_NAMESPACE}" --timeout=300s \
  || { echo "ERROR: eventing-controller did not become Ready. Aborting."; exit 1; }

echo "Waiting for eventing-webhook in ${EVENTING_NAMESPACE} (300s timeout) ..."
kubectl rollout status deployment/eventing-webhook \
  -n "${EVENTING_NAMESPACE}" --timeout=300s \
  || { echo "ERROR: eventing-webhook did not become Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 3a: Knative Kafka Broker plugin — controller
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3a] Installing Kafka Broker controller (${KAFKA_BROKER_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KAFKA_BROKER_VERSION}/eventing-kafka-controller.yaml" \
  || { echo "ERROR: Failed to apply Kafka Broker controller. Aborting."; exit 1; }

echo "Waiting for kafka-controller in ${EVENTING_NAMESPACE} (300s timeout) ..."
kubectl rollout status deployment/kafka-controller \
  -n "${EVENTING_NAMESPACE}" --timeout=300s \
  || { echo "ERROR: kafka-controller did not become Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 3b: Knative Kafka Broker plugin — data-plane
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3b] Installing Kafka Broker data-plane (${KAFKA_BROKER_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KAFKA_BROKER_VERSION}/eventing-kafka-broker.yaml" \
  || { echo "ERROR: Failed to apply Kafka Broker data-plane. Aborting."; exit 1; }

echo "Waiting for kafka-broker-receiver in ${EVENTING_NAMESPACE} (300s timeout) ..."
kubectl rollout status deployment/kafka-broker-receiver \
  -n "${EVENTING_NAMESPACE}" --timeout=300s \
  || { echo "ERROR: kafka-broker-receiver did not become Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
echo ""
echo "Knative Eventing + Kafka Broker plugin installed successfully."
