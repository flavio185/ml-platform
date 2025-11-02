export ISTIO_VERSION=1.26

helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm install istio-base istio/base -n istio-system --wait --set defaultRevision=${ISTIO_VERSION} --create-namespace --version ${ISTIO_VERSION}
helm install istiod istio/istiod -n istio-system --wait --version ${ISTIO_VERSION} \
   --set proxy.autoInject=disabled \
   --set-string pilot.podAnnotations."cluster-autoscaler\.kubernetes\.io/safe-to-evict"=true
helm install istio-ingressgateway istio/gateway -n istio-system --version ${ISTIO_VERSION} \
   --set-string podAnnotations."cluster-autoscaler\.kubernetes\.io/safe-to-evict"=true

# Wait for the istio ingressgateway pod to be created
sleep 10
# Wait for istio ingressgateway to be ready
kubectl wait --for=condition=Ready pod -l app=istio-ingressgateway -n istio-system --timeout=600s
echo "😀 Successfully installed Istio"