# Kafka

Installs a single-broker [Kafka](https://kafka.apache.org/) cluster via [Strimzi](https://strimzi.io/) on AKS. Kafka is the messaging backend for the Knative Kafka Broker that routes KServe inference payload CloudEvents to consumer services.

## Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Strimzi Cluster Operator | 0.50.1 | Manages Kafka lifecycle on Kubernetes |
| Kafka | 4.1.1 (KRaft) | Message broker — no ZooKeeper (removed in Kafka 4.0) |

## Contents

| File | Purpose |
|------|---------|
| `setup-kafka.sh` | Installs Strimzi Operator and creates the Kafka cluster |
| `kafka-cluster.yaml` | `KafkaNodePool` (combined controller+broker) + `Kafka` CR |

## Install

```bash
bash Kafka/setup-kafka.sh
```

## Bootstrap address

After install, the bootstrap service is available cluster-internally at:

```
kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
```

This address is pre-configured in `Inference/KNative/kafka-broker-config.yaml`.

## Architecture

Kafka 4.x uses KRaft (Kafka Raft Metadata) — ZooKeeper was removed. A single `KafkaNodePool` with combined `controller` + `broker` roles runs in one pod, which is sufficient for development and staging.

```
KafkaNodePool (dual-role)
  ├── role: controller   (KRaft metadata quorum)
  └── role: broker       (message storage + serving)
```

## Verify

```bash
kubectl get kafka -n kafka
kubectl get kafkanodepool -n kafka
kubectl get svc kafka-cluster-kafka-bootstrap -n kafka
```

## Notes

- Storage is `ephemeral` — Kafka data is lost on pod restart. For production, change `storage.type` to `persistent-claim` with an Azure Disk PVC.
- Must be installed **before** `Inference/KNative/PayloadLogging/setup-payload-logging.sh`
