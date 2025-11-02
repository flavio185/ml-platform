SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
export SCRIPT_DIR

kubectl apply -k ${SCRIPT_DIR}/prometheus-operator
kubectl wait --for condition=established --timeout=120s crd/prometheuses.monitoring.coreos.com
kubectl wait --for condition=established --timeout=120s crd/servicemonitors.monitoring.coreos.com
kubectl apply -k ${SCRIPT_DIR}/prometheus