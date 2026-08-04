#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Setting up Feast Infrastructure"
echo "-----------------------------------"

# 1. Redis (standalone for now; scale-up: bitnami/redis-cluster with 6 nodes)
echo "Deploying Redis for Feast online store..."
kubectl create namespace feast-ns --dry-run=client -o yaml | kubectl apply -f -

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update bitnami

helm upgrade --install redis bitnami/redis -n feast-ns \
  --set architecture=standalone \
  --set auth.enabled=false \
  --set master.persistence.size=5Gi \
  --wait --timeout 120s

echo "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n feast-ns --timeout=120s || true

# 2. Dedicated PostgreSQL for Feast SQL registry (independent from MLflow's)
echo "Deploying dedicated PostgreSQL for Feast registry..."
kubectl apply -f "$SCRIPT_DIR/postgres-deployment.yaml"

echo "Waiting for Feast PostgreSQL..."
kubectl wait --for=condition=available deployment/feast-postgresql -n feast-ns --timeout=180s
kubectl wait --for=condition=ready pod -l app=feast-postgresql -n feast-ns --timeout=120s

echo "✅ Feast registry database ready on dedicated PostgreSQL"

# 3. Apply feature_store.yaml ConfigMap before starting the server
echo "Creating Feast feature-store config..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: feast-feature-store-config
  namespace: feast-ns
data:
  feature_store.yaml: |
    project: ml_platform
    registry:
      registry_type: sql
      path: postgresql+psycopg2://feast:feast@feast-postgresql.feast-ns.svc.cluster.local:5432/feast_registry
    provider: local
    online_store:
      type: redis
      connection_string: "redis-master.feast-ns.svc.cluster.local:6379"
    offline_store:
      type: file
    entity_key_serialization_version: 2
EOF

# 4. Feast feature server (1 replica, no HPA — scale-up: add HPA min 2 / max 10)
echo "Deploying Feast feature server..."
kubectl apply -f "$SCRIPT_DIR/feast-server-deployment.yaml"

echo "Waiting for Feast server..."
kubectl wait --for=condition=available deployment/feast-server -n feast-ns --timeout=180s

echo "✅ Feast infrastructure setup complete"
echo "  Redis: redis-master.feast-ns.svc.cluster.local:6379"
echo "  Feature server: feast-server.feast-ns.svc.cluster.local:6566"
echo "  Registry: feast-postgresql.feast-ns.svc.cluster.local:5432/feast_registry"
