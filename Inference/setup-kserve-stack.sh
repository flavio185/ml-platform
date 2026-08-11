#!/usr/bin/env bash
# File: setup-kserve-stack.sh
# Purpose: Install the full inference stack in dependency order
# Run from the ml-platform/ root directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

# --- Required path: everything a KServe InferenceService needs to serve traffic ---
# bash "${SCRIPT_DIR}/GatewayAPI/setup-gatewayapi.sh"
bash "${SCRIPT_DIR}/CertManager/setup-certmanager.sh"
bash "${SCRIPT_DIR}/Istio/setup-istio.sh"
bash "${SCRIPT_DIR}/KNativeServing/setup-knative-serving.sh"
bash "${SCRIPT_DIR}/KServe/setup-kserve.sh"
bash "${SCRIPT_DIR}/MetricsMonitoring/setup-kserve-metrics-and-monitoring.sh"

# --- Optional path: only needed for CloudEvent-driven features (currently: payload capture) ---
# Skip this whole block if you don't need inference payload archiving — model
# serving above works fully without it.
bash "${ROOT_DIR}/Kafka/setup-kafka.sh"
bash "${SCRIPT_DIR}/KNativeEventing/setup-knative-eventing.sh"
bash "${SCRIPT_DIR}/PayloadArchiving/setup-payload-archiving.sh"

# Generic install ends here — no demo namespace (app-ns) or demo model
# (sklearn-iris) is deployed by this script. Any project's InferenceService
# pointed at the shared Broker already gets its payloads captured. The iris
# demo is a separate, optional, manually-run smoke test — see Test/README.md.
