#!/usr/bin/env bash
# File: teardown-kserve-stack.sh
# Purpose: Tear down the full inference stack in safe reverse-dependency order.
#          Does NOT touch: monitoring, kuberay, mlflow, kube-system.
#
# WARNING: Step 8 removes Istio and the istio-system namespace entirely, and
# step 10 removes the Gateway API CRDs. Other repos outside this one
# (kubernetes-gitops, kubernetes-mlflow, kubernetes-observability) install
# their own NGINX Gateway Fabric + Gateway/HTTPRoute resources for
# mlflow/argocd/argo-workflows/grafana — NGF is unaffected by this script,
# but double-check nothing else in your cluster still expects
# istio-ingressgateway (e.g. a Gateway API Gateway using gatewayClassName:
# istio) before running this.

set -euo pipefail

echo "kubectl context: $(kubectl config current-context)"
echo ""
read -r -p "This will DESTROY the inference stack. Confirm? [yes/N]: " CONFIRM
[[ "${CONFIRM}" == "yes" ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# Step 1 — KServe
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 1] Uninstalling KServe ..."
helm uninstall kserve-resources -n kserve 2>/dev/null || true
helm uninstall kserve           -n kserve 2>/dev/null || true  # old chart name
kubectl delete namespace kserve --wait=true --timeout=120s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 2 — Knative Kafka Broker data-plane
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 2] Removing Knative Kafka Broker data-plane (v1.14.1) ..."
kubectl delete -f \
  "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.14.1/eventing-kafka-broker.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 3 — Knative Kafka Broker controller
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 3] Removing Knative Kafka Broker controller (v1.14.1) ..."
kubectl delete -f \
  "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.14.1/eventing-kafka-controller.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 4 — Knative Eventing
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 4] Removing Knative Eventing core + CRDs (v1.14.1) ..."
kubectl delete -f \
  "https://github.com/knative/eventing/releases/download/knative-v1.14.1/eventing-core.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl delete -f \
  "https://github.com/knative/eventing/releases/download/knative-v1.14.1/eventing-crds.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 5 — Knative Serving (net-istio + core + CRDs)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 5] Removing net-istio + Knative Serving (v1.14.1) ..."
kubectl delete -f \
  "https://github.com/knative/net-istio/releases/download/knative-v1.14.1/net-istio.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl delete -f \
  "https://github.com/knative/serving/releases/download/knative-v1.14.1/serving-core.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl delete -f \
  "https://github.com/knative/serving/releases/download/knative-v1.14.1/serving-crds.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 6 — Force-delete remaining Knative namespaces (finalizer-safe)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 6] Deleting Knative namespaces ..."
for ns in knative-eventing knative-serving; do
  if kubectl get namespace "${ns}" &>/dev/null; then
    echo "  Deleting namespace ${ns} ..."
    # Patch out any stuck finalizers on the namespace itself
    kubectl patch namespace "${ns}" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl delete namespace "${ns}" --wait=true --timeout=120s 2>/dev/null || true
  fi
done

# ---------------------------------------------------------------------------
# Step 7 — Kafka (Strimzi)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 7] Removing Kafka cluster + Strimzi operator ..."
# Delete the Kafka CR first so Strimzi can clean up topics/brokers
kubectl delete kafka kafka-cluster -n kafka --ignore-not-found --timeout=120s 2>/dev/null || true

# Remove Strimzi operator manifests (removes CRDs + ClusterRoles too)
curl -sL "https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.50.1/strimzi-cluster-operator-0.50.1.yaml" \
  | sed "s/namespace: myproject/namespace: kafka/g" \
  | kubectl delete -f - --ignore-not-found --timeout=60s 2>/dev/null || true

echo "  Deleting namespace kafka ..."
kubectl delete namespace kafka --wait=true --timeout=120s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 8 — Istio
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 8] Uninstalling Istio ..."
helm uninstall istio-ingressgateway -n istio-system 2>/dev/null || true
helm uninstall istiod               -n istio-system 2>/dev/null || true
helm uninstall istio-base           -n istio-system 2>/dev/null || true
kubectl delete namespace istio-system --wait=true --timeout=120s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 9 — Cert Manager
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 9] Uninstalling Cert Manager ..."
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
kubectl delete namespace cert-manager --wait=true --timeout=120s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 10 — Gateway API CRDs (v1.2.1 — the installed version)
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 10] Removing Gateway API CRDs (v1.2.1) ..."
kubectl delete -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml" \
  --ignore-not-found --timeout=60s 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 11 — Leftover cluster-scoped resources
# ---------------------------------------------------------------------------
echo ""
echo ">>> [Step 11] Cleaning up leftover cluster-scoped resources ..."

# Knative CRDs (serving, eventing, kafka-broker)
kubectl get crd -o name 2>/dev/null \
  | grep -E "knative\.dev|eventing\.knative|messaging\.knative|sources\.knative|flows\.knative" \
  | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

# Strimzi CRDs
kubectl get crd -o name 2>/dev/null \
  | grep "strimzi\|kafka\.strimzi" \
  | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

# Knative ClusterRoles / ClusterRoleBindings
kubectl get clusterrole,clusterrolebinding -o name 2>/dev/null \
  | grep "knative" \
  | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

# Knative ValidatingWebhookConfigurations / MutatingWebhookConfigurations
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration -o name 2>/dev/null \
  | grep "knative" \
  | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

# inference-logging (payload-archiver consumer namespace — owned by Inference/,
# unlike app-ns which is a separate, optional demo namespace with its own
# lifecycle managed by app-ns/setup-app-ns.sh)
kubectl delete namespace inference-logging --wait=true --timeout=60s 2>/dev/null || true

# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "Inference stack removed. Remaining namespaces:"
kubectl get namespaces
echo "════════════════════════════════════════════════════════════════════════"
