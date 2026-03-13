# Ray

Installs [KubeRay](https://ray-project.github.io/kuberay/) on the cluster and provides the `RayJob` manifests for distributed model training.

## Components installed

| Release | Chart | Version | Purpose |
|---------|-------|---------|---------|
| `kuberay-operator` | `kuberay/kuberay-operator` | 1.4.2 | Manages `RayCluster` and `RayJob` lifecycle |
| `kuberay-apiserver` | `kuberay/kuberay-apiserver` | 1.4.0 | REST API for submitting and querying Ray jobs |

The operator is installed with `metrics.serviceMonitor.enabled=true` so Prometheus automatically scrapes Ray cluster metrics.

## Install

```bash
bash Ray/setup-ray.sh
```

## RayJob manifests

| File | Purpose |
|------|---------|
| `ray-chart/ray-model-training-job.yaml` | Basic `RayJob` — runs `uv run project-cli full-pipeline` |
| `ray-model-training-job-monitoring.yaml` | `RayJob` with Fluent Bit sidecar — ships logs to Loki |

### Submit a training job

```bash
kubectl apply -f Ray/ray-model-training-job-monitoring.yaml -n app-ns
```

Monitor progress:

```bash
kubectl get rayjob -n app-ns
kubectl logs -l ray.io/node-type=head -n app-ns -c ray-head -f
```

## Job configuration

Key fields in the `RayJob` spec:

| Field | Value | Description |
|-------|-------|-------------|
| `entrypoint` | `uv run project-cli full-pipeline` | Runs Bronze → Silver → Features → Training |
| `working_dir` | S3 zip package path | Downloaded from S3 by Ray runtime env |
| `shutdownAfterJobFinishes` | `true` | Ephemeral cluster — deleted after job completes |
| `ttlSecondsAfterFinished` | `80` | Seconds before cluster resources are garbage-collected |
| `rayVersion` | `2.46.0` | Must match the `rayproject/ray` image tag |

## Log persistence

The monitoring job variant attaches a Fluent Bit sidecar to both head and worker pods. Fluent Bit tails `/tmp/ray/session_latest/logs/*` and ships logs to Loki (`loki.monitoring.svc.cluster.local:3100`), preserving them after the ephemeral cluster is deleted.

```
Ray head/worker pods → Fluent Bit sidecar → Loki → Grafana
```

The `fluentbit-config` ConfigMap is defined in `app-ns/fluentbit-config.yaml`.

## Dependencies

- AKS cluster running and kubeconfig configured
- `app-ns` namespace with `aws-credentials` secret (`app-ns/setup-app-ns.sh`)
- MLflow tracking server running (`MLFlow/`)
- Observability stack installed for log collection (`Observability/setup-monitoring.sh`)
