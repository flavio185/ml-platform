# README.md: ml-project-scaffold

## 1. Objetivo do Case

O objetivo deste **ML Project Scaffold** é prover uma fundação de engenharia de Machine Learning (MLOps) robusta, padronizada e *cloud-native*. Ele automatiza o ciclo de vida completo do ML, desde o pré-processamento distribuído e treinamento até a inferência escalável e observabilidade aprofundada, garantindo **reprodutibilidade**, **escalabilidade** e **eficiência** de recursos em um ambiente **Azure Kubernetes Service (AKS)**.

## 2. Arquitetura de Solução e Arquitetura Técnica

A arquitetura é construída sobre um *stack* de código aberto e *cloud-native*, orquestrado pelo Kubernetes no AKS.

| Componente | Função | Tecnologias Chave |
| :--- | :--- | :--- |
| **Infraestrutura** | Orquestração e Cluster Management. | **AKS (Azure Kubernetes Service)**, **Kubernetes** |
| **Computação Distribuída** | Treinamento e Pré-processamento de alto desempenho. | **Ray** |
| **Inferência Online** | Servidor de modelos escalável e Serverless. | **KServe** (com **Knative** e **Istio**) |
| **Gerenciamento de Modelos** | Rastreamento de experimentos, registro e versionamento de modelos. | **MLflow** |
| **Backend MLflow** | Banco de dados para *tracking* de metadados. | **PostgreSQL** |
| **Artifact Store** | Armazenamento de modelos (artefatos). | **Minio** (compatível com S3) |
| **Data Lake** | Armazenamento de dados de treinamento. | **S3** (Azure Blob Storage compatível) |
| **CI/CD** | Automação dos pipelines de treinamento e deployment. | **GitHub Actions** |
| **Observabilidade** | Logs, Métricas e Dashboards. | **Prometheus**, **Grafana**, **Loki**, **Ray Log Offloader** |

### Fluxo Arquitetural Chave:

1.  **Treinamento Distribuído:** Uma **GitHub Action** é acionada, submetendo o job de treinamento para um cluster **Ray** efêmero no AKS. O Ray executa pré-processamento e treinamento lendo os dados diretamente do **S3**.
2.  **Model Management:** Ao final do treinamento, o modelo é salvo no **Minio** (via MLflow) e os metadados da execução são registrados no **PostgreSQL** (via MLflow).
3.  **Data Lineage Leve:** Para garantir a rastreabilidade sem inflacionar o MLflow, **apenas os metadados dos dados de treinamento (local, nome, versão)** são logados no MLflow, enquanto os dados brutos permanecem no S3.
4.  **Inferência Serverless:** Outra **GitHub Action** implanta o modelo no **KServe**. O KServe, via **Knative**, habilita o *auto-scaling* e o *scale-to-zero*, expondo o serviço através do **Istio**.

## 3. Explicação sobre o Case Desenvolvido (Plano de Implementação)

O *scaffold* oferece uma estrutura de código e IaC (Infrastructure as Code) para garantir que novos projetos herdem automaticamente as melhores práticas de MLOps.

### A. Treinamento e Pré-processamento com Ray
* **Execução via GitHub Actions:** O fluxo de CI/CD utiliza GitHub Actions para encapsular o código de treinamento em uma imagem e submeter um **RayJob** no Kubernetes, facilitando a execução de treinamentos distribuídos e *hyperparameter tuning* sem a necessidade de gerenciar o ciclo de vida do cluster Ray manualmente.
* **Ray Datasets/Train:** O código de treinamento é escrito para aproveitar as bibliotecas nativas do Ray para otimizar a leitura de dados do S3 e o treinamento distribuído (ex: `Ray.data` e `Ray.train`).

### B. Inferência Online Serverless com KServe
* **Deployment Otimizado:** O KServe é a camada de serving, configurado para consumir o modelo diretamente do **Minio**.
* **Escalabilidade e Eficiência:** O uso de **Knative** permite que o serviço de inferência escale de zero a N réplicas em segundos, otimizando o custo quando não há tráfego e garantindo baixa latência em picos de demanda.
* **Roteamento:** **Istio** é usado para gerenciar o tráfego de entrada (InferenceService Ingress), permitindo roteamento de tráfego, políticas de segurança e futuras implementações de *canary deployment*.

### C. Observabilidade e Persistência de Logs
* **Logs Persistentes (Ray Offloader)::** Um componente crítico é o **Ray Log Offloader**. Ele garante que, mesmo após a finalização do Ray Cluster (que é efêmero após a conclusão do job), os logs de todos os workers e do head node sejam descarregados e persistidos em um armazenamento secundário (DuckDB/Minio). Isso é fundamental para o *debugging* e a auditoria de jobs de treinamento passados.
* **Inference Metrics:** O KServe é integrado ao **Prometheus** para expor métricas de inferência cruciais (latência, taxa de erro HTTP, volume de requisições). Essas métricas são visualizadas no **Grafana**.
* **Tabela de Inferência:** O *serving runtime* está configurado para registrar o *payload* completo de cada inferência (entradas, saídas, *timestamps* e ID do modelo) em uma "tabela de inferência" (geralmente um banco de dados analítico como o DuckDB com dados no Minio), servindo como uma fonte de dados para **análise de desvio de modelo (drift)** e **auditoria de decisões**.

## 4. Melhorias e Considerações Finais

### Melhorias a Serem Implementadas:

1.  **Feature Store (Ex: Feast/Hopsworks):** Adicionar uma Feature Store para garantir a consistência das *features* usadas no pré-processamento e na inferência, além de simplificar o *data lineage*.
2.  **Monitoramento de Drift:** Integrar uma ferramenta de monitoramento de ML (ex: Evidently, WhyLabs) que leia os dados da Tabela de Inferência para alertas automáticos de desvio de dados (*data drift*) e de modelo (*model drift*).
3.  **Deployment Estratégico:** Implementar pipelines Blue/Green ou Canary automatizados, utilizando os recursos de roteamento de tráfego do Istio/KServe, para mitigar riscos durante a implantação de novos modelos em produção.
4.  **Autenticação Reforçada:** Implementar autenticação e autorização (RBAC) mais robustas para acesso aos endpoints do MLflow e aos serviços do KServe.

### Considerações Finais:

Este projeto estabelece um padrão moderno de MLOps. A escolha de tecnologias como Ray e KServe aborda diretamente os requisitos de **escalabilidade** para grandes volumes de dados (Ray) e **eficiência operacional** para inferência (KServe/Knative). A arquitetura de observabilidade, com persistência de logs de jobs efêmeros e coleta de dados de inferência, garante que a plataforma seja **auditável** e **confiável** para ambientes produtivos.