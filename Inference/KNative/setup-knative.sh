#!/usr/bin/env bash
# File: setup-knative.sh
# Purpose: Install Knative Serving (with net-istio) + Knative Eventing + Kafka Broker plugin
# Dependencies: kubectl configured and connected to the target AKS cluster;
#               Istio already installed (Inference/Istio/setup-istio.sh)

set -euo pipefail

KNATIVE_VERSION="v1.21.2"
KAFKA_BROKER_VERSION="v1.21.2"
# net-istio releases independently and may lag one patch behind Knative Serving
NET_ISTIO_VERSION="v1.21.1"
NAMESPACE="knative-serving"

# ---------------------------------------------------------------------------
# Step 1: Ensure namespace exists (do NOT recreate if already present)
# ---------------------------------------------------------------------------
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "Namespace '${NAMESPACE}' already exists — skipping creation."
else
  echo "Creating namespace '${NAMESPACE}' ..."
  kubectl create namespace "${NAMESPACE}" \
    || { echo "ERROR: Failed to create namespace '${NAMESPACE}'. Aborting."; exit 1; }
fi

# ---------------------------------------------------------------------------
# Step 2: Knative Serving CRDs
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 2] Installing Knative Serving CRDs (${KNATIVE_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml" \
  || { echo "ERROR: Failed to apply Knative Serving CRDs. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 3: Knative Serving core
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3] Installing Knative Serving core (${KNATIVE_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml" \
  || { echo "ERROR: Failed to apply Knative Serving core. Aborting."; exit 1; }

echo "Waiting for serving deployments in ${NAMESPACE} (120s timeout) ..."
for deploy in controller webhook activator; do
  kubectl rollout status deployment/${deploy} -n "${NAMESPACE}" --timeout=120s \
    || { echo "ERROR: ${deploy} did not become Ready. Aborting."; exit 1; }
done

# ---------------------------------------------------------------------------
# Step 4: net-istio (Knative Serving ingress via Istio)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 4] Installing net-istio (${NET_ISTIO_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative/net-istio/releases/download/knative-${NET_ISTIO_VERSION}/net-istio.yaml" \
  || { echo "ERROR: Failed to apply net-istio. Aborting."; exit 1; }

# Configure Istio as the ingress class
kubectl patch configmap config-network \
  -n "${NAMESPACE}" \
  --type merge \
  -p '{"data":{"ingress-class":"istio.ingress.networking.knative.dev"}}' \
  || { echo "ERROR: Failed to patch config-network. Aborting."; exit 1; }

# Set a wildcard domain so InferenceService URLs resolve via the IngressGateway IP
kubectl patch configmap config-domain \
  -n "${NAMESPACE}" \
  --type merge \
  -p '{"data":{"example.com":""}}' \
  || { echo "ERROR: Failed to patch config-domain. Aborting."; exit 1; }

# Two separate keys, both default to "none" and must be set independently:
#   - request-metrics-protocol: queue-proxy's PER-REQUEST metrics (revision_*
#     request latency/concurrency series). Confirmed empirically these land
#     on the predictor's http-usermetric port (9091) once enabled --
#     ../MetricsMonitoring/kserve-service-monitor.yaml scrapes that port.
#     NOT http-autometric (9090): that port is queue-proxy's internal-only
#     OpenCensus/protobuf channel feeding the autoscaler, and stays protobuf
#     regardless of this setting (confirmed via GIT_CURL_VERBOSE-style
#     tracing -- Content-Type: application/protobuf even with this set).
#   - metrics-protocol: the autoscaler/controller/webhook components' OWN
#     metrics (autoscaler_actual_pods, autoscaler_desired_pods, etc., on the
#     autoscaler Service's http-metrics port 9090 -- confirmed via
#     connection-refused until this was set). Also scraped by
#     ../MetricsMonitoring/kserve-service-monitor.yaml's
#     knative-autoscaler-monitoring ServiceMonitor.
# NB: both are Knative 1.21+ keys -- the old metrics.backend-destination key
# from pre-OTel Knative versions no longer applies and is silently ignored.
kubectl patch configmap config-observability \
  -n "${NAMESPACE}" \
  --type merge \
  -p '{"data":{"request-metrics-protocol":"prometheus","metrics-protocol":"prometheus"}}' \
  || { echo "ERROR: Failed to patch config-observability. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 5: Knative Eventing CRDs
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 5] Installing Knative Eventing CRDs (${KNATIVE_VERSION}) ..."
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
# Step 6: Knative Eventing core
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 6] Installing Knative Eventing core (${KNATIVE_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml" \
  || { echo "ERROR: Failed to apply Knative Eventing core. Aborting."; exit 1; }

_eventing_ns="knative-eventing"
if ! kubectl get namespace knative-eventing &>/dev/null; then
  _eventing_ns="${NAMESPACE}"
fi

echo "Waiting for eventing-controller in ${_eventing_ns} (60s timeout) ..."
kubectl rollout status deployment/eventing-controller \
  -n "${_eventing_ns}" --timeout=300s \
  || { echo "ERROR: eventing-controller did not become Ready. Aborting."; exit 1; }

echo "Waiting for eventing-webhook in ${_eventing_ns} (60s timeout) ..."
kubectl rollout status deployment/eventing-webhook \
  -n "${_eventing_ns}" --timeout=300s \
  || { echo "ERROR: eventing-webhook did not become Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 7: Knative Kafka Broker plugin — controller
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 7a] Installing Kafka Broker controller (${KAFKA_BROKER_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KAFKA_BROKER_VERSION}/eventing-kafka-controller.yaml" \
  || { echo "ERROR: Failed to apply Kafka Broker controller. Aborting."; exit 1; }

echo "Waiting for kafka-controller in ${_eventing_ns} (60s timeout) ..."
kubectl rollout status deployment/kafka-controller \
  -n "${_eventing_ns}" --timeout=300s \
  || { echo "ERROR: kafka-controller did not become Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
# Step 8: Knative Kafka Broker plugin — data-plane
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 7b] Installing Kafka Broker data-plane (${KAFKA_BROKER_VERSION}) ..."
kubectl apply -f \
  "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KAFKA_BROKER_VERSION}/eventing-kafka-broker.yaml" \
  || { echo "ERROR: Failed to apply Kafka Broker data-plane. Aborting."; exit 1; }

echo "Waiting for kafka-broker-receiver in ${_eventing_ns} (60s timeout) ..."
kubectl rollout status deployment/kafka-broker-receiver \
  -n "${_eventing_ns}" --timeout=300s \
  || { echo "ERROR: kafka-broker-receiver did not become Ready. Aborting."; exit 1; }

# ---------------------------------------------------------------------------
echo ""
echo "Knative Serving + Eventing + Kafka Broker plugin installed successfully."
