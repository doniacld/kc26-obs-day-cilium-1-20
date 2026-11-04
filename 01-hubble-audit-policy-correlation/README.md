# 01 - Hubble Policy Correlation for Audit Verdicts

See which policy would have denied a flow before you turn enforcement on.

> **Cilium 1.20** | [#45373](https://github.com/cilium/cilium/pull/45373) by [@Rajneesh180](https://github.com/Rajneesh180)

Before 1.20, a flow logged under Policy Audit Mode showed up in Hubble with its
policy fields empty: you saw the flow would have been denied, not which policy
would have denied it. Now audit verdicts (`Verdict_AUDIT`) fill
`ingress_denied_by` / `egress_denied_by`, and `--print-policy-names` prints
`AUDITED BY <policy>`.

## Prerequisites

Completed [00-setup](../00-setup/), Hubble port-forward running, and a host
Hubble CLI 1.20+ (older CLIs do not render `AUDITED BY`).

## How It Works

1. **Policy Audit Mode** on the deathstar endpoints: denies are logged, not enforced
2. **Three policies** ([cnp.yaml](cnp.yaml)): `rule1` (ingress allow), `deny-alliance` (ingress deny), `xwing-egress` (egress allow)
3. **Hubble** names the matching policy on every verdict

| Verdict | Printed as | JSON field |
|---|---|---|
| `FORWARDED` | `ALLOWED BY` | `ingress_allowed_by` / `egress_allowed_by` |
| `DROPPED` | `DENIED BY` | `ingress_denied_by` / `egress_denied_by` |
| `AUDIT` (new in 1.20) | `AUDITED BY` | `ingress_denied_by` / `egress_denied_by` |

## Run the Demo

```bash
cd 01-hubble-audit-policy-correlation
bash demo.sh
```

## Manual Steps

Enable audit mode on a deathstar endpoint (repeat per node it runs on):

```bash
kubectl -n kube-system exec <cilium-pod> -- cilium-dbg endpoint config <deathstar-endpoint-id> PolicyAuditMode=Enabled
```

Apply the policies and send traffic:

```bash
kubectl apply -f cnp.yaml
kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
```

The curl succeeds (audit mode), but Hubble names the policy that would have blocked it:

```bash
hubble observe --type policy-verdict --verdict AUDIT --print-policy-names
```

Expected output:
```
default/xwing:36272 -> default/deathstar-86f85ffb4d-6ktgx:80 policy-verdict:L3-Only INGRESS AUDITED BY deny-alliance (CiliumNetworkPolicy) (TCP Flags: SYN)
```

As structured data:

```bash
hubble observe --type policy-verdict --verdict AUDIT -o json | jq '.flow.ingress_denied_by'
```

More outputs, including the allowed and enforced-deny cases: [output-examples.md](output-examples.md).

## Scope

Correlation names the policy that *matched* a flow: allows, explicit
`ingressDeny` / `egressDeny`, and now audit verdicts. A default deny (no allow
matched, drop reason 133) has no policy to name and is not correlated.

## Visual Example

![Hubble audit policy correlation demo](demo-01-audit-correlation.gif)

Final screen as a still: [audit-correlation-final.png](audit-correlation-final.png).
The recording is also on [asciinema](https://asciinema.org/a/gOciMB63yizy2ix6)
([demo-01-audit-correlation.cast](demo-01-audit-correlation.cast)).

To regenerate the GIF from the recording with [agg](https://github.com/asciinema/agg):
```bash
agg --theme dracula --font-size 20 --idle-time-limit 3 demo-01-audit-correlation.cast demo-01-audit-correlation.gif
```

Or record `demo.sh` with [VHS](https://github.com/charmbracelet/vhs):
```bash
vhs demo-01-audit-correlation.txt
```

**Use cases**: rolling out deny policies safely, validating policy changes in audit mode, explaining drops during incidents.

## References

- [Creating policies from verdicts](https://docs.cilium.io/en/v1.20/security/policy-creation/#creating-policies-from-verdicts)
- [Policy Audit Mode](https://docs.cilium.io/en/v1.20/security/policy-creation/#enable-policy-audit-mode-specific-endpoint)

Next: [02-ztunnel-metrics](../02-ztunnel-metrics/)
