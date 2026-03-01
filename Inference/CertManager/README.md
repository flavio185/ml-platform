# CertManager

Installs [cert-manager](https://cert-manager.io/) into the cluster. cert-manager is a required dependency for KServe — it issues and rotates TLS certificates for the KServe webhook server.

## Version

cert-manager **v1.16.1**

## Install

```bash
bash Inference/CertManager/setup-certmanager.sh
```

Installs cert-manager into the `cert-manager` namespace via the Jetstack Helm chart with CRD installation enabled.

## Verify

```bash
kubectl get pods -n cert-manager
# cert-manager, cert-manager-cainjector, cert-manager-webhook should all be Running
```

## Notes

- Must be installed **before** KServe (`Inference/KServe/setup-kserve.sh`)
- The CRDs (`certificates.cert-manager.io`, `clusterissuers.cert-manager.io`, etc.) are installed by the Helm chart via `--set crds.enabled=true`
