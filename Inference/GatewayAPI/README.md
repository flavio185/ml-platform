# GatewayAPI

Installs the [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) CRDs into the cluster. The Gateway API is a required dependency for Istio and KServe routing.

## Version

Gateway API **v1.2.1** (standard channel)

## Install

```bash
bash Inference/GatewayAPI/setup-gatewayapi.sh
```

Applies the standard Gateway API CRDs directly from the upstream release manifest.

## CRDs installed

- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`
- `grpcroutes.gateway.networking.k8s.io`

## Notes

- Must be installed **before** Istio (`Inference/Istio/setup-istio.sh`)
- This step installs CRDs only — no controllers are deployed here; Istio provides the Gateway API implementation
