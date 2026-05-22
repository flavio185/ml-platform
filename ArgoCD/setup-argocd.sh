#!/bin/bash
set -euo pipefail

echo "🚀 Setting up Argo CD"
echo "-----------------------------------"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: the applicationsets.argoproj.io CRD is larger than the 256 KiB
# annotation limit used by client-side apply (last-applied-configuration), which
# causes: 'metadata.annotations: Too long: may not be more than 262144 bytes'.
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD server..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s || true

# Apply the ApplicationSet that auto-manages all ML projects
echo "Applying ApplicationSet..."
kubectl apply -f "$(dirname "$0")/applicationset.yaml"

echo "✅ Argo CD setup complete"
echo ""
echo "To access Argo CD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "  Initial admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
