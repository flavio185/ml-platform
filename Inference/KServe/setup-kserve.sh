SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
export SCRIPT_DIR

export KSERVE_VERSION=v0.15.2
deploymentMode="Serverless"

helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd --version ${KSERVE_VERSION} --namespace kserve --create-namespace --wait
helm install kserve oci://ghcr.io/kserve/charts/kserve --version ${KSERVE_VERSION} --namespace kserve --create-namespace --wait \
   --set-string kserve.controller.deploymentMode="${deploymentMode}"

kubectl apply -f ${SCRIPT_DIR}/configmap.yaml