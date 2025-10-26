NAMESPACE="app-ns"

kubectl create namespace $NAMESPACE 

kubectl create secret generic aws-credentials \
  --namespace $NAMESPACE \
  --from-literal=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  --from-literal=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

kubectl label namespace $NAMESPACE istio-injection=enabled

for i in $(ls app-ns | grep yaml); do
  echo "🚀 Applying $i in $NAMESPACE"
  kubectl apply -f app-ns/"$i" -n $NAMESPACE
done