# Istio

Installs the [Istio](https://istio.io/) service mesh into the cluster. Istio provides the `IngressGateway` that routes external traffic to KServe `InferenceService` pods via Knative.

## Version

Istio **v1.26**

## Components installed

| Release | Chart | Namespace | Purpose |
|---------|-------|-----------|---------|
| `istio-base` | `istio/base` | `istio-system` | CRDs and cluster-wide resources |
| `istiod` | `istio/istiod` | `istio-system` | Control plane (Pilot, Citadel, Galley) |
| `istio-ingressgateway` | `istio/gateway` | `istio-system` | External LoadBalancer ingress |

## Install

```bash
bash Inference/Istio/setup-istio.sh
```

## Configuration notes

- `proxy.autoInject=disabled` — Istio sidecar injection is opt-in per namespace (enabled via the `istio-injection=enabled` label; every project namespace sets this in its own `gitops/namespace.yaml`, e.g. `ml-credit-default`)
- `cluster-autoscaler.kubernetes.io/safe-to-evict=true` — allows the cluster autoscaler to evict Istio pods on scale-down events

## Verify

```bash
kubectl get pods -n istio-system
kubectl get svc istio-ingressgateway -n istio-system
# EXTERNAL-IP should be populated (Azure LoadBalancer)
```

## Notes

- Must be installed **before** Knative Serving (`../KNativeServing/`) and KServe — Knative Eventing (`../KNativeEventing/`) has no dependency on Istio
- The IngressGateway external IP is used by `Inference/Test/test.sh` to route inference requests
