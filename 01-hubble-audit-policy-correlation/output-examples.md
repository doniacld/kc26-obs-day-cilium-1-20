# Hubble policy correlation: output examples

Representative `hubble observe` output for each verdict case with Cilium 1.20
and the Star Wars demo (`baseline-allow` permits empire-to-empire web traffic
clusterwide, while `allow-empire` is specific to deathstar TCP 80;
`deny-alliance` explicitly denies alliance).

## Use case 1: AUDIT verdict names the policy that would have denied

Audit mode enabled on the deathstar endpoints, `deny-alliance` applied.

```console
$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict AUDIT --print-policy-names
Jul 15 10:11:40.451: default/xwing:40218 (ID:41050) <> default/deathstar:80 (ID:11009) policy-verdict:L3-Only INGRESS AUDITED BY deny-alliance (CiliumNetworkPolicy) (TCP Flags: SYN)
```

Same correlation as structured data:

```console
$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict AUDIT -o json | jq '.flow.ingress_denied_by'
[
  {
    "name": "deny-alliance",
    "namespace": "default",
    "labels": [
      "k8s:io.cilium.k8s.policy.derived-from=CiliumNetworkPolicy",
      "k8s:io.cilium.k8s.policy.name=deny-alliance",
      "k8s:io.cilium.k8s.policy.namespace=default",
      "k8s:io.cilium.k8s.policy.uid=8f3c1d2e-4a5b-6c7d-8e9f-0a1b2c3d4e5f"
    ],
    "revision": 7,
    "kind": "CiliumNetworkPolicy"
  }
]
```

## Use case 2: all matching allow policies are named

The clusterwide `baseline-allow` accepts TCP 80 and 443 traffic between empire
workloads across namespaces. The namespaced `allow-empire` permits empire
traffic specifically to deathstar on TCP 80. Both match the request from
`tiefighter`:

```console
$ kubectl apply -f cnp.yaml
$ kubectl apply -f baseline-allow-ccnp.yaml
$ kubectl exec tiefighter -- curl -s -o /dev/null -w '%{http_code}\n' -XPOST deathstar.default.svc.cluster.local/v1/request-landing
200
```

When more than one policy allows a flow, Hubble names all matching policies:

```console
$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict FORWARDED --print-policy-names
Nov  6 18:56:37.068: default/tiefighter:59264 (ID:19915) -> default/deathstar-86f85ffb4d-hxct5:80 (ID:29762) policy-verdict:L3-L4 INGRESS ALLOWED BY baseline-allow (CiliumClusterwideNetworkPolicy), allow-empire (CiliumNetworkPolicy) (TCP Flags: SYN)
```

The order of policy names can vary. The same two entries appear in the
`ingress_allowed_by` JSON field. The xwing's allowed egress is named separately
as `xwing-egress`.

## Use case 3: enforced explicit deny

Audit mode disabled, `deny-alliance` applied.

```console
$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict DROPPED --print-policy-names
Jul 15 10:14:02.118: default/xwing:55700 (ID:41050) <> default/deathstar:80 (ID:11009) policy-verdict:L3-Only INGRESS DENIED BY deny-alliance (CiliumNetworkPolicy) (TCP Flags: SYN)
```

```console
$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict DROPPED -o json \
    | jq '{verdict:.flow.verdict, reason:.flow.drop_reason_desc, denied_by:[.flow.ingress_denied_by[].name]}'
{
  "verdict": "DROPPED",
  "reason": "POLICY_DENY",
  "denied_by": ["deny-alliance"]
}
```

`POLICY_DENY` (code 181) is the explicit-deny reason: a deny entry was matched,
which is what makes it attributable.

## Not covered: implicit deny-by-default

An implicit deny (`deny-alliance` deleted, only `allow-empire` left) is not correlated,
and 1.20 did not change that. `DROP_POLICY` (code 133) is returned before any
match type is set, so no policy-map entry was found and there is no policy to
name. Only drops that matched a deny entry (181) carry attribution.

## Formatting reference

The compact line is built by `getVerdict()` and `formatPolicyNames()` in
`hubble/pkg/printer/printer.go`:

| Verdict | Word | Field read with `--print-policy-names` |
|---|---|---|
| `FORWARDED` / `REDIRECTED` | `ALLOWED` | `ingress_allowed_by` / `egress_allowed_by` |
| `DROPPED` / `ERROR` | `DENIED` | `ingress_denied_by` / `egress_denied_by` |
| `AUDIT` | `AUDITED` | `ingress_denied_by` / `egress_denied_by` |

The suffix is `" BY "` followed by `name (Kind)`, comma-separated for multiple
policies, and omitted entirely when the list is empty. The
`policy-verdict:<match>` prefix comes from `PolicyMatchType.String()`: `none`,
`L3-Only`, `L3-L4`, `L4-Only`, `all`, `L3-Proto`, `Proto-Only`.

The arrow is `<>` rather than `->` on dropped and audited SYNs, because
`is_reply` is unset and the printer renders direction as unknown.
