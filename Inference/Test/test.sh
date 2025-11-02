kubectl apply -f Inference/Test/sklearn-iris.yaml -n app-ns

export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SERVICE_HOSTNAME=$(kubectl -n app-ns get inferenceservice sklearn-iris -o jsonpath='{.status.url}' | cut -d "/" -f 3)

MODEL_NAME=sklearn-iris
INPUT_PATH=@./Inference/Test/iris-input.json

curl -v -H "Host: ${SERVICE_HOSTNAME}" -H "Content-Type: application/json" http://${INGRESS_HOST}:${INGRESS_PORT}/v1/models/$MODEL_NAME:predict -d $INPUT_PATH