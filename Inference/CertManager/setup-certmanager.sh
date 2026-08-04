export CERT_MANAGER_VERSION=v1.20.1

# Install Cert Manager
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install \
   cert-manager jetstack/cert-manager \
   --namespace cert-manager \
   --create-namespace \
   --version ${CERT_MANAGER_VERSION} \
   --set crds.enabled=true
echo "😀 Successfully installed Cert Manager"