AKS/aks_cluster_manager.sh createaks
sleep 30
# Get AKS credentials
AKS/aks_cluster_manager.sh getcreds
export KUBECONFIG=$HOME/.kube/config

sleep 5
# Setup Ray
echo "🚀 Setting up Ray"
echo "-----------------------------------"
#
Ray/setup-ray.sh
sleep 30

# Setup MLFlow
echo "🚀 Setting up MLFlow"
echo "-----------------------------------"
#
helm install mlflow MLFlow/mlflow-chart -n mlflow-ns --create-namespace
sleep 30

# Setup KServe
KServe/auto-install-kserve.sh
sleep 30


# Create AWS credentials secret in the app namespace
# get aws credentials from .env file
source .env
