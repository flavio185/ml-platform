
export MLFLOW_TRACKING_URI="http://nginx.mlflow-ns.svc.cluster.local"

#Install a ray job:
#https://docs.ray.io/en/latest/cluster/kubernetes/getting-started/rayjob-quick-start.html#step-3-install-a-rayjob
#Run a test job.
kubectl create namespace app-ns
kubectl config set-context --current --namespace=app-ns

#https://docs.ray.io/en/latest/cluster/kubernetes/getting-started/raycluster-quick-start.html
# Step 3: Deploy a RayCluster custom resource
# Once the KubeRay operator is running, you’re ready to deploy a RayCluster. Create a RayCluster Custom Resource (CR) in the default namespace.

helm install raycluster kuberay/ray-cluster --version 1.3.0 --namespace app-ns


kubectl apply -f https://raw.githubusercontent.com/ray-project/kuberay/v1.4.2/ray-operator/config/samples/ray-job.shutdown.yaml -n app-ns
kubectl apply -f https://raw.githubusercontent.com/ray-project/kuberay/v1.4.2/ray-operator/config/samples/ray-job.sample.yaml -n app-ns

kubectl get raycluster -n app-ns


# kubectl port-forward service/rayjob-sample-pararell-raycluster-rmzmb-head-svc 8265:8265 > /dev/null &