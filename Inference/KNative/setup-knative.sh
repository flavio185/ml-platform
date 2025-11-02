export KNATIVE_OPERATOR_VERSION=v1.15.7
export KNATIVE_SERVING_VERSION=1.15.2

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
export SCRIPT_DIR

helm install knative-operator --namespace knative-serving --create-namespace --wait \
      https://github.com/knative/operator/releases/download/knative-${KNATIVE_OPERATOR_VERSION}/knative-operator-${KNATIVE_OPERATOR_VERSION}.tgz

kubectl apply -f ${SCRIPT_DIR}/knative-serving.yaml

echo "Waiting for Knative Serving to be ready ..."
kubectl wait --for=condition=Available=True --timeout=600s deployment --all -n knative-serving

echo "Installing Knative Message Dumper ..."
kubectl apply -f ${SCRIPT_DIR}/message-dumper.yaml -n knative-serving