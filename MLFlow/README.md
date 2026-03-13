# MLFlow

Helm chart deployment for the MLflow experiment tracking and model registry stack.

## Stack

| Component | Purpose | Storage |
|-----------|---------|---------|
| **MLflow** | Experiment tracking, model registry, artifact logging | — |
| **PostgreSQL** | MLflow metadata backend (runs, params, metrics) | Azure Disk PVC |
| **MinIO** | Artifact store (models, plots, preprocessor configs) | Azure Disk PVC |
| **NGINX** | Reverse proxy — single entry point for MLflow UI and MinIO console | — |

## Install

```bash
helm install mlflow MLFlow/mlflow-chart/ -n mlflow-ns --create-namespace
```

Upgrade:

```bash
helm upgrade mlflow MLFlow/mlflow-chart/ -n mlflow-ns
```

## Accessing services

After install, use `kubectl port-forward` or the NGINX service external IP:

```bash
# MLflow UI
kubectl port-forward svc/nginx -n mlflow-ns 5000:80

# MinIO console
kubectl port-forward svc/minio -n mlflow-ns 9001:9001
```

## Configuration

All values are in `mlflow-chart/values.yaml`. Key settings:

| Value | Description |
|-------|-------------|
| `mlflow.image.tag` | MLflow Docker image version |
| `postgresql.auth.*` | PostgreSQL credentials |
| `minio.auth.*` | MinIO root user and password |
| `minio.persistence.storageClass` | Storage class for the MinIO PVC (default: Azure Disk) |
| `postgresql.persistence.storageClass` | Storage class for the PostgreSQL PVC |

## MLflow tracking URI

From within the cluster (e.g. from a RayJob in `app-ns`):

```
http://nginx.mlflow-ns.svc.cluster.local
```

## Contents

```
MLFlow/
└── mlflow-chart/          # Helm chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── mlflow/        # MLflow Deployment + Service + ConfigMap
        ├── postgres/      # PostgreSQL Deployment + Service + PVC + Secret
        ├── minio/         # MinIO Deployment + Service + PVC + Secret + bucket init Job
        └── nginx/         # NGINX Deployment + Service + ConfigMap
```
