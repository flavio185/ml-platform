Setup environment.

az login

AKS/aks_cluster_manager.sh createaks

AKS/aks_cluster_manager.sh createaksnodepool

AKS/aks_cluster_manager.sh getcreds

kubectl get nodes
export KUBECONFIG=$HOME/.kube/config

# Configure free-lens

# Install mlflow
helm install  mlflow MLFlow/mlflow-chart/ -n mlflow-ns --create-namespace

# Install ray
Ray/setup-ray.sh 

# Install Kserve
KServe/auto-install-kserve.sh

# Install Observability stack
kubectl apply -f Observability/namespace.yaml
Observability/Grafana/setup.sh
Observability/Prometheus/setup.sh
Observability/Loki/setup.sh