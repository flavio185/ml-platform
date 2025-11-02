export GATEWAY_API_VERSION=v1.2.1

echo "Installing Gateway API CRDs ..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml
echo "Gateway API CRDs installed."