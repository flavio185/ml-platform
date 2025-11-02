export CERT_MANAGER_VERSION=v1.16.1

# Install Cert Manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm install \
   cert-manager jetstack/cert-manager \
   --namespace cert-manager \
   --create-namespace \
   --version ${CERT_MANAGER_VERSION} \
   --set crds.enabled=true
echo "😀 Successfully installed Cert Manager"