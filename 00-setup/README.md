# 00 - Setup

Create a kind cluster with Cilium 1.20 and deploy the demo workloads.

## Prerequisites

kind, helm 3, kubectl, docker, jq, Hubble CLI 1.20+

## What Gets Installed

- 3-node kind cluster (1 control-plane, 2 workers) running Kubernetes 1.33
- Cilium 1.20.4 ([values.yaml](values.yaml)) with:
  - Hubble relay for observability (demo 01)
  - ztunnel encryption for sidecarless mTLS (demo 02)
  - Prometheus metrics on the agent, port 9962 (demo 02)
- The Star Wars demo app in `default`: `deathstar`, `tiefighter` (empire), `xwing` (alliance)

Demo 02 creates its own `mtls-demo` namespace.

## Run Setup

```bash
cd 00-setup
bash install-cilium.sh
```

Override the version with `CILIUM_VERSION=1.20.x bash install-cilium.sh`.

## Verify Installation

```bash
cilium status
kubectl get pods -o wide
```

Start the Hubble port-forward and verify:

```bash
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &
hubble status
```

Next: [01-hubble-audit-policy-correlation](../01-hubble-audit-policy-correlation/)

## References

- [Cilium Installation Guide](https://docs.cilium.io/en/v1.20/gettingstarted/k8s-install-default/)
- [Hubble Setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/)
- [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
