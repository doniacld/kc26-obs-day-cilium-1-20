#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

DEATHSTAR="deathstar.default.svc.cluster.local"

pause() { echo ""; read -r -p "Press ENTER to continue..."; }

# Flip Policy Audit Mode on every deathstar endpoint, on whichever node it runs.
set_audit() {
  local p id found=0
  for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
    for id in $(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg endpoint list -o json 2>/dev/null \
        | jq -r '.[] | select((.status.labels."security-relevant" // []) | any(.=="k8s:class=deathstar")) | .id'); do
      printf '%b$ kubectl -n kube-system exec %s -c cilium-agent -- \\\n' "$CYAN" "$p"
      printf '    cilium-dbg endpoint config %s PolicyAuditMode=%s%b\n' "$id" "$1" "$NC"
      kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg endpoint config "$id" PolicyAuditMode="$1" >/dev/null
      found=1
    done
  done
  if (( found == 0 )); then
    echo "No deathstar endpoints found on any Cilium agent." >&2
    return 1
  fi
}

show_audit() {
  local p id mode found=0
  for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      mode=$(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg endpoint config "$id" 2>/dev/null \
        | awk -F: '/PolicyAuditMode/ { gsub(/[[:space:]]/, "", $2); print $2; exit }')
      printf '  deathstar endpoint %s on %s: PolicyAuditMode=%s\n' "$id" "${p#pod/}" "${mode:-unknown}"
      found=1
    done < <(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg endpoint list -o json 2>/dev/null \
      | jq -r '.[] | select((.status.labels."security-relevant" // []) | any(.=="k8s:class=deathstar")) | .id')
  done
  if (( found == 0 )); then
    echo "  No deathstar endpoints found on any Cilium agent."
  fi
}

landing() {
  kubectl exec "$1" -- curl -s -m 6 -o /dev/null -w '%{http_code}\n' -XPOST "${DEATHSTAR}/v1/request-landing" 2>/dev/null || echo "failed"
}

# Hide kubectl port-forward diagnostics on success, but surface connection errors.
hubble_observe() {
  local error_log status=0
  error_log=$(mktemp)
  hubble observe --port-forward --port-forward-port 0 "$@" 2>"$error_log" || status=$?
  if ((status != 0)); then
    cat "$error_log" >&2
  fi
  rm -f "$error_log"
  return "$status"
}

# Off screen: start from the allow-empire policy only.
kubectl delete cnp deny-alliance xwing-egress --ignore-not-found >/dev/null
kubectl delete ccnp baseline-allow --ignore-not-found >/dev/null
kubectl apply -f allow-empire-only.yaml >/dev/null

clear
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}DEMO 1: Hubble Policy Correlation for Audit Verdicts${NC}"
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${WHITE}Policy Audit Mode logs what a policy would block without enforcing it.${NC}"
echo -e "${WHITE}In Cilium 1.20, Hubble names the policy behind every audit verdict.${NC}"
pause

clear
echo -e "${GREEN}Step 1: Enable Policy Audit Mode on the deathstar endpoints${NC}"
echo ""
echo -e "${WHITE}Set PolicyAuditMode on each deathstar endpoint:${NC}"
set_audit Enabled
echo ""
echo -e "${WHITE}Verify the setting on each endpoint:${NC}"
show_audit
pause

clear
echo -e "${GREEN}Step 2: Apply a clusterwide baseline and traffic-specific policies${NC}"
echo ""
echo -e "${CYAN}$ kubectl apply -f cnp.yaml${NC}"
kubectl apply -f cnp.yaml
echo ""
echo -e "${CYAN}$ kubectl apply -f baseline-allow-ccnp.yaml${NC}"
kubectl apply -f baseline-allow-ccnp.yaml
echo ""
echo -e "${CYAN}$ kubectl get cnp -n default${NC}"
kubectl get cnp -n default
echo ""
echo -e "${CYAN}$ kubectl get ccnp baseline-allow${NC}"
kubectl get ccnp baseline-allow
echo ""
echo "  allow-empire  allow empire -> deathstar:80"
echo "  baseline-allow  allow empire web traffic clusterwide (TCP 80/443)"
echo "  deny-alliance deny alliance -> deathstar"
echo "  xwing-egress  allow xwing -> deathstar:80 and kube-dns"
sleep 5
pause

clear
echo -e "${YELLOW}Step 3: Send traffic from both ships${NC}"
echo ""
echo -e "${CYAN}$ kubectl exec xwing -- curl -XPOST ${DEATHSTAR}/v1/request-landing${NC}"
landing xwing
echo -e "${CYAN}$ kubectl exec tiefighter -- curl -XPOST ${DEATHSTAR}/v1/request-landing${NC}"
landing tiefighter
echo ""
echo "The xwing gets through: audit mode does not enforce the deny."
sleep 3
pause

clear
echo -e "${YELLOW}Step 4: See the AUDIT policy in text and structured data${NC}"
echo ""
echo -e "${CYAN}$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict AUDIT --print-policy-names --last 20${NC}"
echo ""
audit_text=''
for ((attempt=0; attempt<10; attempt++)); do
  audit_text=$(hubble_observe --type policy-verdict --verdict AUDIT --print-policy-names --last 20)
  if grep -q 'xwing.*AUDITED BY deny-alliance' <<< "$audit_text"; then
    break
  fi
  echo "Waiting for the xwing AUDIT verdict..."
  kubectl exec xwing -- curl -s -m 6 -o /dev/null -XPOST "${DEATHSTAR}/v1/request-landing" >/dev/null 2>&1 || true
  sleep 2
done
if ! grep -q 'xwing.*AUDITED BY deny-alliance' <<< "$audit_text"; then
  echo "Hubble did not observe an xwing AUDIT verdict for deny-alliance." >&2
  exit 1
fi
grep xwing <<< "$audit_text" | tail -1 | grep --color=always -E 'AUDITED BY [^ ]+|$'
echo ""
echo -e "${WHITE}The same policy names are available as structured data:${NC}"
echo -e "${CYAN}$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict AUDIT -o json --last 20 | jq '.flow.ingress_denied_by'${NC}"
echo ""
hubble_observe --type policy-verdict --verdict AUDIT -o json --last 20 \
  | jq -se '[.[] | select(.flow.source.pod_name=="xwing" and ((.flow.ingress_denied_by // []) | length > 0))] | if length == 0 then error("No correlated xwing AUDIT verdict") else .[-1].flow.ingress_denied_by | map({name, namespace, kind}) end'
pause

clear
echo -e "${YELLOW}Step 5: Allowed flows are named too, per direction${NC}"
echo ""
echo -e "${CYAN}$ hubble observe --port-forward --port-forward-port 0 --type policy-verdict --verdict FORWARDED --print-policy-names --last 50 | grep deathstar | tail -2${NC}"
echo ""
hubble_observe --type policy-verdict --verdict FORWARDED --print-policy-names --last 50 \
  | grep deathstar | tail -2 | grep --color=always -E 'ALLOWED BY|baseline-allow|allow-empire|xwing-egress|$'
echo ""
echo -e "${WHITE}The clusterwide baseline and deathstar-specific allow are both named.${NC}"
pause

clear
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Audit verdicts name the policy that would have denied the flow${NC}"
echo -e "${GREEN}✅ Available as text (--print-policy-names) and JSON (*_denied_by)${NC}"
echo -e "${GREEN}✅ Allowed flows are correlated in both directions${NC}"
echo -e "${GREEN}✅ Preview exactly what a policy will block before enforcing it${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
