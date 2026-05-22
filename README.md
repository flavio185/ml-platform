# ml-platform

Infraestrutura Kubernetes para a plataforma de MLOps da DataMaster2026. Provisiona todos os componentes necessarios para treinar, servir e monitorar modelos de Machine Learning em **Azure Kubernetes Service (AKS)**.

## Arquitetura

| Componente | Funcao | Tecnologias |
| :--- | :--- | :--- |
| **Infraestrutura** | Cluster e orquestracao | AKS, Kubernetes |
| **Orquestracao de Pipelines** | DAGs de ML (bronze -> gold -> training) | **Argo Workflows** + ClusterWorkflowTemplates |
| **Continuous Delivery** | GitOps — sync automatico de manifests | **Argo CD** + ApplicationSet |
| **Retraining Automatico** | Evento de drift dispara pipeline | **Argo Events** (EventSource + Sensor) |
| **Feature Store** | Consistencia de features treino/inferencia | **Feast** (SQL registry, Redis online, file offline) |
| **Computacao Distribuida** | Treinamento pesado sob demanda | **Ray** (KubeRay) |
| **Inferencia Online** | Serving escalavel e serverless | **KServe** (Knative + Istio) |
| **Gerenciamento de Modelos** | Tracking, registro, versionamento | **MLflow** (PostgreSQL + Minio) |
| **Observabilidade** | Logs, metricas, dashboards | Prometheus, Grafana, Loki |
| **Streaming** | Payload logging de inferencia | Kafka |

### Fluxo Arquitetural

```
GitHub Actions (CI)
  |-- lint + test
  |-- Docker build + push (GHCR)
  └-- Commit image tag no ml-platform-gitops
         |
         v
Argo CD (CD)
  |-- Detecta mudanca no gitops repo
  |-- Sync automatico (prune + selfHeal)
  └-- Cria/atualiza recursos no namespace ml-{projeto}
         |
         v
Argo Workflows (Orquestracao)
  |-- DAG: bronze -> silver -> validate -> features -> training
  |-- CronWorkflow diario
  └-- Argo Events: drift -> retraining automatico
         |
         v
Feast (Feature Store)              MLflow (Model Registry)
  |-- Offline: S3 parquet            |-- Tracking de metricas
  |-- Online: Redis                  |-- Registro de modelos
  └-- Registry: PostgreSQL           └-- Artefatos no Minio
         |                                    |
         v                                    v
KServe (Inferencia)
  |-- Modelo do MLflow/Minio
  |-- Features do Feast online store
  |-- Scale 0-N (Knative)
  └-- Payload logging (Kafka)
```

## Estrutura do Repositorio

```
ml-platform/
|-- AKS/                          # Provisionamento do cluster AKS
|-- ArgoWorkflows/
|   |-- setup-argo-workflows.sh   # Instala controller + Argo Events
|   |-- rbac.yaml                 # ClusterRole para workflows em namespaces ml-*
|   └-- cluster-workflow-templates.yaml  # Templates compartilhados:
|                                        #   container-step, rayjob-step, feast-materialize
|-- ArgoCD/
|   |-- setup-argocd.sh           # Instala Argo CD
|   └-- applicationset.yaml       # Git directory generator (projects/*)
|
|-- Feast/
|   |-- setup-feast.sh            # Redis standalone + DB feast_registry + feature server
|   └-- feast-server-deployment.yaml  # Deployment + Service do feature server
|
|-- base-image/
|   └-- Dockerfile                # Imagem base compartilhada (Python 3.12 + feast + mlflow + ray)
|
|-- Ray/                          # KubeRay operator e configuracao
|-- MLFlow/                       # MLflow server (Helm) + PostgreSQL + Minio
|-- Inference/
|   └── KNative/                  # KServe + Knative + Istio + triggers
|-- Kafka/                        # Kafka para payload logging
|-- Observability/                # Prometheus + Grafana + Loki
|-- app-ns/                       # Namespace legado (migrado para ml-{projeto})
|
└-- setup.sh                      # Script principal — provisiona tudo em ordem
```

## Instalacao

```bash
# Provisiona cluster AKS e todos os componentes
./setup.sh
```

O `setup.sh` executa na seguinte ordem:
1. AKS cluster + kubeconfig
2. Ray (KubeRay operator)
3. MLflow (Helm: server + PostgreSQL + Minio)
4. KServe + Knative + Istio
5. Feast (Redis + DB registry + feature server)
6. Argo Workflows (controller + Events + templates compartilhados)
7. Argo CD (controller + ApplicationSet)

## Componentes Detalhados

### Argo Workflows

Orquestra os pipelines de ML como DAGs Kubernetes. Fornece **ClusterWorkflowTemplates** compartilhados:

| Template | Descricao | Uso |
| :--- | :--- | :--- |
| `container-step` | Execucao generica em container com retry | Todos os steps por padrao |
| `rayjob-step` | Submete RayJob e aguarda conclusao | Opt-in para treinamento distribuido |
| `feast-materialize` | Aplica definicoes e materializa features | Step de features |

Cada projeto define seu proprio `WorkflowTemplate` (DAG) e `CronWorkflow` no gitops repo.

### Argo CD + GitOps

O **ApplicationSet** com Git directory generator monitora `ml-platform-gitops/projects/*`. Adicionar um diretorio = provisionar automaticamente:

```
ml-platform-gitops/
  base/                          # Kustomize base compartilhado
  projects/
    credit-default/              # ml-default-payment-project
      kustomization.yaml
      namespace.yaml             # Namespace + ResourceQuota + RBAC
      argo-workflow.yaml         # WorkflowTemplate DAG
      cron-workflow.yaml         # Pipeline agendado
      argo-events.yaml           # Retraining por drift
      kserve-inference.yaml      # InferenceService
    # novos projetos adicionados aqui pelo scaffold
```

### Feast

Configuracao minima, arquitetada para escalar:

| Componente | Atual | Escala para | Mudanca necessaria |
| :--- | :--- | :--- | :--- |
| Offline store | `file` (PyArrow no S3) | `spark` no Ray | 1 linha no YAML |
| Online store | Redis standalone | Redis Cluster (6+ nos) | Helm chart swap |
| Registry | SQL (PostgreSQL) | Mesmo (ja correto) | — |
| Feature server | 1 replica | HPA min 2 / max 10 | Adicionar HPA manifest |

### Namespace por Projeto

Cada projeto ML roda em namespace isolado `ml-{projeto}` com:
- **ResourceQuota**: CPU, memoria, pods
- **ServiceAccount** dedicado para Argo Workflows
- **RoleBinding** com permissoes minimas (pods, workflows, rayjobs)

### Imagem Base Compartilhada

```dockerfile
# ml-platform/base-image/Dockerfile
FROM python:3.12-slim
# Inclui: feast[redis], mlflow, ray, pandas, scikit-learn, great-expectations, etc.
```

Publicada em `ghcr.io/datamaster2026/ml-platform-base:latest`. Projetos individuais estendem esta imagem com suas dependencias especificas.

## Caminhos de Escala

| Componente | Atual (minimo) | Escala para | Mudanca |
| :--- | :--- | :--- | :--- |
| AKS nodes | 2-6 (autoscaler) | Node pools dedicados (platform, workload, spot) | Adicionar node pools |
| Argo Workflow steps | `container-step` (pod unico) | `rayjob-step` (Ray distribuido) | Mudar 1 templateRef |
| Feast online store | Redis standalone | Redis Cluster | Helm chart swap |
| Feast feature server | 1 replica | HPA 2-10 replicas | Adicionar HPA |
| Feast offline store | `file` (PyArrow) | `spark` no Ray | 1 linha no YAML |
| ResourceQuota | Limites generosos | Ajustados por projeto | Config |
| KServe | Scale 0-5 | Mais replicas + HPA | Config |

## Melhorias Futuras

1. **Monitoramento de Drift**: Integrar Evidently/WhyLabs com a tabela de inferencia para alertas automaticos de data drift e model drift
2. **Deployment Estrategico**: Pipelines Blue/Green ou Canary automatizados via Istio/KServe
3. **Autenticacao Reforcada**: RBAC mais robusto para MLflow e KServe
4. **Node Pools Dedicados**: Pools separados para platform services, workloads e spot instances
