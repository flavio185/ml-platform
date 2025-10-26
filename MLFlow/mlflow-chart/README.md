Absolutely, FLAVIO! Here's a dynamic Helm README template that uses `{{ .Values }}` placeholders for customization and includes badges for GitHub and Docker Hub. This version is designed to be dropped into your Helm chart repo and automatically reflect your values and deployment setup.

---

# 📦 MLflow Helm Chart with PostgreSQL, MinIO, and NGINX

[![Docker Hub](https://img.shields.io/badge/Docker-flavio185%2Fmlflow-blue?logo=docker)](https://hub.docker.com/repository/docker/flavio185/mlflow/general)  
[![GitHub](https://img.shields.io/badge/GitHub-helm--chart-lightgrey?logo=github)](https://github.com/flavio185/helm-chart)

This Helm chart deploys a full MLflow stack with:

- **MLflow v{{ .Values.mlflow.image.tag }}**
- **PostgreSQL v{{ .Values.postgresql.image.tag }}**
- **MinIO v{{ .Values.minio.image.tag }}**
- **NGINX v{{ .Values.nginx.image.tag }}**

---

## 🔧 Components

| Component   | Purpose |
|------------|---------|
| **MLflow**  | Experiment tracking and artifact logging |
| **PostgreSQL** | Metadata storage |
| **MinIO**   | Artifact storage |
| **NGINX**   | Reverse proxy |
| **Helm**    | Deployment manager |
| **Kubernetes** | Container orchestration |

---

## 🚀 Installation

```bash
helm install {{ .Values.release.name }} {{ .Values.repo.name }}/{{ .Values.chart.name }} \
  --namespace {{ .Values.namespace }} \
  --create-namespace
```

---

## 🌐 Accessing Services

- **MLflow UI**: `http://{{ .Values.ingress.host }}/`
- **MinIO Console**: `http://{{ .Values.ingress.host }}/minio/`

If using local DNS:

```
127.0.0.1 {{ .Values.ingress.host }}
```

---

## 🔍 MLflow API Endpoints

```http
POST /api/2.0/mlflow/experiments/create
POST /api/2.0/mlflow/runs/create
POST /api/2.0/mlflow/runs/log-params
POST /api/2.0/mlflow/runs/log-metric
GET  /api/2.0/mlflow/artifacts/list
```

---

## 🗃️ PostgreSQL Access

```bash
kubectl exec -n {{ .Values.namespace }} -it <postgres-pod> -- \
  psql -U {{ .Values.postgresql.auth.username }} -d {{ .Values.postgresql.auth.database }}
```

---

## 📁 MinIO Access

```bash
kubectl exec -n {{ .Values.namespace }} -it <minio-pod> -- \
  mc alias set local http://localhost:9000 {{ .Values.minio.auth.rootUser }} {{ .Values.minio.auth.rootPassword }}
mc ls local/mlflow
```

---

## 🌐 NGINX Proxy Config

```nginx
location / {
  proxy_pass http://mlflow:{{ .Values.mlflow.service.port }};
}
location /minio/ {
  proxy_pass http://minio:{{ .Values.minio.service.port }}/;
}
```

---

## 🧪 MLflow Example

```python
import mlflow

mlflow.set_tracking_uri("http://{{ .Values.ingress.host }}")
mlflow.set_experiment("demo")

with mlflow.start_run():
    mlflow.log_param("alpha", 0.5)
    mlflow.log_metric("rmse", 0.75)
    mlflow.log_artifact("model.pkl")
```

