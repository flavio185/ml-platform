SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
export SCRIPT_DIR

export KSERVE_VERSION=v0.15.2
deploymentMode="Serverless"

helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd --version ${KSERVE_VERSION} --namespace kserve --create-namespace --wait
helm install kserve oci://ghcr.io/kserve/charts/kserve --version ${KSERVE_VERSION} --namespace kserve --create-namespace --wait \
   --set-string kserve.controller.deploymentMode="${deploymentMode}"

# Wait for the KServe webhook server to be ready before applying cluster resources
echo "Waiting for KServe webhook server to be ready..."
kubectl wait --for=condition=ready pod \
  -l control-plane=kserve-controller-manager \
  -n kserve \
  --timeout=300s

# Install built-in ClusterServingRuntimes (sklearn, xgboost, lgbm, etc.)
kubectl apply -f https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve-cluster-resources.yaml
kubectl wait --for condition=established --timeout=120s crd/clusterservingruntimes.serving.kserve.io 2>/dev/null || true

kubectl apply -f ${SCRIPT_DIR}/configmap.yaml