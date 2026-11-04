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
  local p id
  for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
    for id in $(kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg endpoint list -o json 2>/dev/null \
        | jq -r '.[] | select((.status.labels."security-relevant" // []) | any(.=="k8s:class=deathstar")) | .id'); do
      kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg endpoint config "$id" PolicyAuditMode="$1" >/dev/null
    done
  done
}

landing() {
  kubectl exec "$1" -- curl -s -m 6 -o /dev/null -w '%{http_code}\n' -XPOST "${DEATHSTAR}/v1/request-landing" 2>/dev/null || echo "failed"
}

# Off screen: start from rule1 only, deathstar in Policy Audit Mode.
kubectl delete cnp deny-alliance xwing-egress --ignore-not-found >/dev/null
kubectl apply -f rule1-only.yaml >/dev/null
set_audit Enabled

clear
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}DEMO 1: Hubble Policy Correlation for Audit Verdicts${NC}"
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${WHITE}Policy Audit Mode logs what a policy would block without enforcing it.${NC}"
echo -e "${WHITE}In Cilium 1.20, Hubble names the policy behind every audit verdict.${NC}"
pause

clear
echo -e "${GREEN}Step 1: The deathstar endpoints are in Policy Audit Mode${NC}"
echo ""
echo -e "${CYAN}$ kubectl -n kube-system exec ds/cilium -- cilium-dbg endpoint list | grep -E 'POLICY|deathstar'${NC}"
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg endpoint list 2>/dev/null | grep -E 'POLICY|deathstar' || true
echo ""
echo "Policy enforcement shows 'Disabled (Audit)': denies are logged, not enforced."
pause

clear
echo -e "${GREEN}Step 2: Apply an ingress allow, an ingress deny and an egress allow${NC}"
echo ""
echo -e "${CYAN}$ kubectl apply -f cnp.yaml${NC}"
kubectl apply -f cnp.yaml
echo ""
echo "  rule1         allow empire -> deathstar:80"
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
echo -e "${YELLOW}Step 4: The AUDIT verdict names the policy that WOULD have denied it${NC}"
echo ""
echo -e "${CYAN}$ hubble observe --type policy-verdict --verdict AUDIT --print-policy-names --last 20${NC}"
echo ""
hubble observe --type policy-verdict --verdict AUDIT --print-policy-names --last 20 2>/dev/null \
  | grep xwing | grep --color=always -E 'AUDITED BY [^ ]+|$' || echo "(no AUDIT verdict yet, re-run in a few seconds)"
pause

clear
echo -e "${YELLOW}Step 5: The same correlation as structured data${NC}"
echo ""
echo -e "${CYAN}$ hubble observe --type policy-verdict --verdict AUDIT -o json --last 20 | jq '.flow.ingress_denied_by'${NC}"
echo ""
hubble observe --type policy-verdict --verdict AUDIT -o json --last 20 2>/dev/null \
  | jq -s '[.[] | select(.flow.source.pod_name=="xwing")] | .[-1].flow.ingress_denied_by | map({name, namespace, kind})'
pause

clear
echo -e "${YELLOW}Step 6: Allowed flows are named too, per direction${NC}"
echo ""
echo -e "${CYAN}$ hubble observe --type policy-verdict --verdict FORWARDED --print-policy-names --last 50${NC}"
echo ""
hubble observe --type policy-verdict --verdict FORWARDED --print-policy-names --last 50 2>/dev/null \
  | grep deathstar | grep --color=always -E 'ALLOWED BY [^ ]+|$' | tail -4
pause

clear
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Audit verdicts name the policy that would have denied the flow${NC}"
echo -e "${GREEN}✅ Available as text (--print-policy-names) and JSON (*_denied_by)${NC}"
echo -e "${GREEN}✅ Allowed flows are correlated in both directions${NC}"
echo -e "${GREEN}✅ Preview exactly what a policy will block before enforcing it${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
