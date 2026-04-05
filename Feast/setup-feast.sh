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

# 2. Feast registry database on existing MLflow PostgreSQL
echo "Creating Feast registry database..."

# Wait for PostgreSQL to be ready before attempting DB creation
POSTGRES_POD=""
for i in $(seq 1 12); do
  POSTGRES_POD=$(kubectl get pod -n mlflow-ns -l app=postgresql \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$POSTGRES_POD" ]; then
    READY=$(kubectl get pod -n mlflow-ns "$POSTGRES_POD" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    [ "$READY" = "True" ] && break
  fi
  echo "  Waiting for PostgreSQL pod... ($i/12)"
  sleep 10
done

if [ -n "$POSTGRES_POD" ]; then
  # Create database (idempotent)
  kubectl exec -n mlflow-ns "$POSTGRES_POD" -- \
    psql -U mlflow -d mlflow-db -tc \
    "SELECT 1 FROM pg_database WHERE datname='feast_registry'" | grep -q 1 || \
  kubectl exec -n mlflow-ns "$POSTGRES_POD" -- \
    psql -U mlflow -d mlflow-db -c "CREATE DATABASE feast_registry;"

  # Create user and grant privileges (idempotent)
  kubectl exec -n mlflow-ns "$POSTGRES_POD" -- \
    psql -U mlflow -d mlflow-db -c \
    "DO \$\$ BEGIN
       IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='feast') THEN
         CREATE USER feast WITH PASSWORD 'feast';
       END IF;
     END \$\$;"

  kubectl exec -n mlflow-ns "$POSTGRES_POD" -- \
    psql -U mlflow -d mlflow-db -c \
    "GRANT ALL PRIVILEGES ON DATABASE feast_registry TO feast;"

  # Grant schema access so feast can create registry tables
  kubectl exec -n mlflow-ns "$POSTGRES_POD" -- \
    psql -U mlflow -d feast_registry -c \
    "GRANT USAGE ON SCHEMA public TO feast;
     GRANT CREATE ON SCHEMA public TO feast;
     ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO feast;"

  echo "✅ Feast registry database ready on shared PostgreSQL"
else
  echo "❌ PostgreSQL not found in mlflow-ns after waiting. Aborting."
  echo "   Ensure MLflow is deployed before running Feast setup."
  exit 1
fi

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
      path: postgresql+psycopg2://feast:feast@postgresql.mlflow-ns.svc.cluster.local:5432/feast_registry
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
echo "  Registry: postgresql.mlflow-ns.svc.cluster.local:5432/feast_registry"
