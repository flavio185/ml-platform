# Update helm repo
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

#Install Operator with Prometheus ServiceMonitor enabled
helm install kuberay-operator kuberay/kuberay-operator --version 1.4.2 \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.serviceMonitor.selector.release=prometheus

# Install KubeRay APIServer
helm install kuberay-apiserver kuberay/kuberay-apiserver --version 1.4.0 --set security=null


# Save logs:
#https://docs.ray.io/en/latest/cluster/kubernetes/user-guides/persist-kuberay-custom-resource-logs.html