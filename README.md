# Cilium 1.20 Observability Features

Hands-on demos for Cilium 1.20 observability with Hubble and Prometheus. Created for KubeCon + CloudNativeCon North America 2026 Observability Day, project updates.

1. **[Hubble Policy Correlation for Audit Verdicts](01-hubble-audit-policy-correlation/)** - See which policy would have denied a flow before enforcing it ([#45373](https://github.com/cilium/cilium/pull/45373) by [@Rajneesh180](https://github.com/Rajneesh180))
2. **[ztunnel mTLS Metrics](02-ztunnel-metrics/)** - Prometheus metrics and a Grafana dashboard for sidecarless mTLS enrollment and health ([#45096](https://github.com/cilium/cilium/pull/45096))

3. **[More Observability](03-more-observability/)** - Features without a demo:
   - **Agent start-up metrics** - Hive lifecycle and Kubernetes resource-sync durations ([#44802](https://github.com/cilium/cilium/pull/44802), [#44639](https://github.com/cilium/cilium/pull/44639) by [@ILL1A](https://github.com/ILL1A))
   - **Standalone DNS Proxy metrics** - DNS metrics exported back through Cilium ([#45222](https://github.com/cilium/cilium/pull/45222), [#44601](https://github.com/cilium/cilium/pull/44601) by [@vipul-21](https://github.com/vipul-21))
   - **`preferIpv6`** - prefer IPv6 for Hubble peering and health probes ([#45447](https://github.com/cilium/cilium/pull/45447) by [@tibrezus](https://github.com/tibrezus))
   - **ConfigMap drift detection** - since 1.18, now with Helm values and docs ([#44703](https://github.com/cilium/cilium/pull/44703) by [@PhilipSchmid](https://github.com/PhilipSchmid))

Full release notes: [Cilium 1.20.0](https://github.com/cilium/cilium/releases/tag/v1.20.0)

## Prerequisites

- kind v0.20+, kubectl v1.28+, helm v3.12+, docker, jq
- Hubble CLI v1.20+
- [VHS](https://github.com/charmbracelet/vhs) to regenerate the GIFs
- 8 GB RAM, 20 GB disk

Install the Hubble CLI:
```bash
# macOS
brew install hubble

# Linux
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin
rm hubble-linux-amd64.tar.gz{,.sha256sum}
```

## Quick Start

```bash
cd 00-setup
bash install-cilium.sh  # Creates a 3-node kind cluster, installs Cilium 1.20.4

kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &
hubble status  # Verify connectivity

cd ../01-hubble-audit-policy-correlation
bash demo.sh  # Run first demo
```

## Cleanup

```bash
kind delete cluster
```

## Resources

- [Cilium 1.20 Release Notes](https://github.com/cilium/cilium/releases/tag/v1.20.0)
- [Cilium 1.20 release blog](https://isovalent.com/blog/post/cilium-1-20/)
- [Hubble Documentation](https://docs.cilium.io/en/v1.20/observability/hubble/)
