# 00 - Setup

Create a kind cluster with Cilium 1.20 and deploy the demo workloads.

## Prerequisites

kind, helm 3, kubectl, docker, jq, Hubble CLI 1.20+

## What Gets Installed

- 3-node kind cluster (1 control-plane, 2 workers) running Kubernetes 1.33
- Cilium 1.20.4 ([values.yaml](values.yaml)) with:
  - Hubble relay and UI for flow observability (demo 01)
  - ztunnel encryption for sidecarless mTLS (demo 02)
  - Prometheus metrics on the agent, port 9962 (demos 02 and 03)
- Prometheus and Grafana for the ztunnel and ConfigMap drift dashboards, with Cilium agent scraping and dashboard provisioning configured automatically
- The Star Wars demo app in `default`: `deathstar`, `tiefighter` (empire), `xwing` (alliance)

## Run Setup

```bash
cd 00-setup
bash install-cilium.sh
```

Override the version with `CILIUM_VERSION=1.20.x bash install-cilium.sh`.
The setup generates cluster-specific ztunnel keys and certificates locally.

## Verify Installation

```bash
cilium status
kubectl get pods -o wide
```

Verify Hubble Relay connectivity:

```bash
hubble status --port-forward --port-forward-port 0
```

Open the Hubble UI:

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

Then visit <http://localhost:12000>.

Open the provisioned ztunnel dashboard in Grafana:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Get the generated Grafana admin password with:

```bash
kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

Visit <http://localhost:3000> and use that password to sign in as `admin`.

The **Cilium ztunnel / native mTLS** and **Cilium ConfigMap drift detection**
dashboards are provisioned automatically. The drift dashboard is at
<http://localhost:3000/d/cilium-config-drift/cilium-configmap-drift-detection>.

Next: [01-hubble-audit-policy-correlation](../01-hubble-audit-policy-correlation/)

## References

- [Cilium Installation Guide](https://docs.cilium.io/en/v1.20/gettingstarted/k8s-install-default/)
- [Hubble Setup](https://docs.cilium.io/en/v1.20/observability/hubble/setup/)
- [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
