# app-ns

Application namespace setup for the ML platform. This namespace (`app-ns`) runs the ML workloads: KServe `InferenceService` resources, RayJob training jobs, and the CloudEvent consumer pipeline.

## Contents

| File | Purpose |
|------|---------|
| `setup-app-ns.sh` | Creates the namespace, injects AWS credentials, enables Istio sidecar injection, and applies all manifests |
| `fluentbit-config.yaml` | Fluent Bit `ConfigMap` — tails Ray session logs from `/tmp/ray` and ships them to Loki |
| `s3creds.yaml` | Secret template for S3/Minio credentials used by KServe storage initializer |
| `s3-sa.yaml` | `ServiceAccount` annotated with S3 credentials for KServe model downloads |
| `service-account.yaml` | Default `ServiceAccount` for workloads running in this namespace |
| `role.yaml` | RBAC `Role` granting RayJob and pod management permissions within `app-ns` |

## Setup

Prerequisites: `.env` file at the repo root with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

```bash
source ../.env
bash app-ns/setup-app-ns.sh
```

What it does:
1. Creates namespace `app-ns`
2. Creates `aws-credentials` secret from env vars
3. Labels the namespace for Istio automatic sidecar injection
4. Applies all YAML manifests in the directory

## Namespace role in the platform

- **Training**: RayJob pods run here, reading training data from S3 via the injected `aws-credentials` secret
- **Inference**: KServe `InferenceService` pods are deployed here; Istio routes traffic through the IngressGateway
- **Observability**: Fluent Bit sidecars on Ray pods ship logs to Loki via the `fluentbit-config` ConfigMap
- **Payload logging**: Consumer services (`payload-archiver`, `drift-detector`, `retraining-trigger`) receive CloudEvents from the Knative Broker
