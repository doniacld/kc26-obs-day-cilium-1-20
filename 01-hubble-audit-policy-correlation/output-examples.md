# Hubble policy correlation: output examples

Expected `hubble observe` output for each verdict case, against Cilium
`v1.20.0-rc.0` with the Star Wars demo (`rule1` allows empire to the deathstar
on TCP 80, `deny-alliance` explicitly denies alliance).

## Use case 1: AUDIT verdict names the policy that would have denied

Audit mode enabled on the deathstar endpoints, `deny-alliance` applied.

```console
$ hubble observe --type policy-verdict --verdict AUDIT --print-policy-names
Jul 15 10:11:40.451: default/xwing:40218 (ID:41050) <> default/deathstar:80 (ID:11009) policy-verdict:L3-Only INGRESS AUDITED BY deny-alliance (CiliumNetworkPolicy) (TCP Flags: SYN)
```

Same correlation as structured data:

```console
$ hubble observe --type policy-verdict --verdict AUDIT -o json | jq '.flow.ingress_denied_by'
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

## Use case 2: allowed flow, for contrast

```console
$ hubble observe --type policy-verdict --verdict FORWARDED --print-policy-names
Jul 15 10:11:38.220: default/tiefighter:52104 (ID:23459) -> default/deathstar:80 (ID:11009) policy-verdict:L3-L4 INGRESS ALLOWED BY rule1 (CiliumNetworkPolicy) (TCP Flags: SYN)
```

When more than one policy allows the flow, all of them are named:

```console
Jul 15 10:11:38.220: default/tiefighter:52104 (ID:23459) -> default/deathstar:80 (ID:11009) policy-verdict:L3-L4 INGRESS ALLOWED BY rule1 (CiliumNetworkPolicy), baseline-allow (CiliumClusterwideNetworkPolicy) (TCP Flags: SYN)
```

## Use case 3: enforced explicit deny

Audit mode disabled, `deny-alliance` applied.

```console
$ hubble observe --type policy-verdict --verdict DROPPED --print-policy-names
Jul 15 10:14:02.118: default/xwing:55700 (ID:41050) <> default/deathstar:80 (ID:11009) policy-verdict:L3-Only INGRESS DENIED BY deny-alliance (CiliumNetworkPolicy) (TCP Flags: SYN)
```

```console
$ hubble observe --type policy-verdict --verdict DROPPED -o json \
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

An implicit deny (`deny-alliance` deleted, only `rule1` left) is not correlated,
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
