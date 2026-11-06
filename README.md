# Cilium 1.20 Observability Features

Hands-on demos for Cilium 1.20 observability with Hubble and Prometheus. Created for KubeCon + CloudNativeCon North America 2026 Observability Day, project updates.

1. **[Hubble Policy Correlation for Audit Verdicts](01-hubble-audit-policy-correlation/)** - See which policy would have denied a flow before enforcing it ([#45373](https://github.com/cilium/cilium/pull/45373) by [@Rajneesh180](https://github.com/Rajneesh180))
2. **[ztunnel mTLS Metrics](02-ztunnel-metrics/)** - Prometheus metrics and a Grafana dashboard for sidecarless mTLS enrollment and health ([#45096](https://github.com/cilium/cilium/pull/45096))
3. **[More Observability](03-more-observability/)** - ConfigMap drift demo in Grafana, plus shorter feature references:
   - **Agent start-up metrics** - Hive lifecycle and Kubernetes resource-sync durations ([#44802](https://github.com/cilium/cilium/pull/44802), [#44639](https://github.com/cilium/cilium/pull/44639) by [@ILL1A](https://github.com/ILL1A))
   - **Standalone DNS Proxy metrics** - DNS metrics exported back through Cilium ([#45222](https://github.com/cilium/cilium/pull/45222), [#44601](https://github.com/cilium/cilium/pull/44601) by [@vipul-21](https://github.com/vipul-21))
   - **`preferIpv6`** - prefer IPv6 for Hubble peering and health probes ([#45447](https://github.com/cilium/cilium/pull/45447) by [@tibrezus](https://github.com/tibrezus))
   - **ConfigMap drift detection** - since 1.18, now with Helm values and docs ([#44703](https://github.com/cilium/cilium/pull/44703) by [@PhilipSchmid](https://github.com/PhilipSchmid))

Full release notes: [Cilium 1.20.0](https://github.com/cilium/cilium/releases/tag/v1.20.0)

## Presentation assets

| Demo | Step screenshots | Terminal GIF | UI screenshot |
|---|---|---|---|
| 1: Hubble audit policy correlation | [PNGs](01-hubble-audit-policy-correlation/README.md#visual-example) | [GIF](01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif) | [Policy diagram](01-hubble-audit-policy-correlation/demo-01-policy-intent.png), [Hubble audit](01-hubble-audit-policy-correlation/hubble-ui-audit-traffic.png), [enforced preview](01-hubble-audit-policy-correlation/hubble-ui-enforced-policy.png) |
| 2: ztunnel mTLS metrics | [PNGs](02-ztunnel-metrics/README.md#visual-example) | [GIF](02-ztunnel-metrics/demo-02-ztunnel-metrics.gif) | [Dashboard PNG](02-ztunnel-metrics/ztunnel-mtls-dashboard.png) |
| 3: ConfigMap drift detection | [PNGs](03-more-observability/README.md#visual-example) | [GIF](03-more-observability/demo-03-config-drift.gif) | [Drift PNG](03-more-observability/config-drift-dashboard.png) |

The GIFs are recorded from the live demo scripts using the `.tape` files in
their directories. Each demo's step PNGs are extracted from its full GIF with
the same [export script](export-presentation-stills.sh). The UI PNGs are
1600×1000 presentation captures. Demo 1
includes both its live audit-mode Hubble view and a temporary enforcement
preview; the Grafana captures show Demo 2 after scaling and Demo 3 while all
three agents report drift.

The full GIFs are preserved. For manually paced slides, use the end-state PNGs
for each step. To regenerate all three recordings and their step screenshots,
run from the repository root:

```bash
(cd 01-hubble-audit-policy-correlation && vhs demo-01-presentation.tape)
(cd 02-ztunnel-metrics && vhs demo-02-ztunnel-metrics.tape)
(cd 03-more-observability && vhs demo-03-config-drift.tape)
./export-presentation-stills.sh
```

Pass `1`, `2`, or `3` to the export script to refresh one demo's screenshots.
The timestamps select settled screens and may need adjustment if a live
recording's timing changes. The UI screenshots are captured separately in
Hubble or Grafana.

## Prerequisites

- kind v0.20+, kubectl v1.28+, helm v3.12+, docker, jq
- Hubble CLI v1.20+
- [VHS](https://github.com/charmbracelet/vhs) and FFmpeg to regenerate the GIFs and step screenshots
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

hubble status --port-forward --port-forward-port 0  # Verify connectivity

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
