#!/usr/bin/env bash
# File: setup-kserve-stack.sh
# Purpose: Install the full inference stack in dependency order
# Run from the ml-platform/ root directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

bash "${SCRIPT_DIR}/GatewayAPI/setup-gatewayapi.sh"
bash "${SCRIPT_DIR}/CertManager/setup-certmanager.sh"
bash "${SCRIPT_DIR}/Istio/setup-istio.sh"
bash "${ROOT_DIR}/Kafka/setup-kafka.sh"
bash "${SCRIPT_DIR}/KNative/setup-knative.sh"
bash "${SCRIPT_DIR}/KServe/setup-kserve.sh"
bash "${SCRIPT_DIR}/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh"
bash "${SCRIPT_DIR}/KNative/PayloadLogging/setup-payload-logging.sh"
