#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

pause() { echo ""; read -r -p "Press ENTER to continue..."; }

# Agent metrics are per node: print each agent's ztunnel series with its node.
ztunnel_metrics() {
  local p node
  for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
    node=$(kubectl -n kube-system get "$p" -o jsonpath='{.spec.nodeName}')
    echo -e "${WHITE}${node}${NC}"
    kubectl -n kube-system exec "$p" -c cilium-agent -- cilium-dbg metrics list 2>/dev/null \
      | grep -E 'ztunnel' | sed 's/^/  /' || echo "  (no ztunnel series yet)"
  done
}

clear
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}DEMO 2: ztunnel mTLS Metrics${NC}"
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${WHITE}Sidecarless mTLS with ztunnel, enrolled per namespace. Cilium 1.20 exports${NC}"
echo -e "${WHITE}Prometheus metrics for enrollment and ztunnel connection health.${NC}"
pause

clear
echo -e "${GREEN}Step 1: Enroll a namespace and deploy client and server on different nodes${NC}"
echo ""
echo -e "${CYAN}$ kubectl apply -f mtls-demo.yaml${NC}"
kubectl apply -f mtls-demo.yaml
kubectl -n mtls-demo rollout status deploy/server deploy/client --timeout=120s >/dev/null
echo ""
echo -e "${CYAN}$ kubectl get ns mtls-demo --show-labels${NC}"
kubectl get ns mtls-demo --show-labels
echo ""
echo -e "${CYAN}$ kubectl -n mtls-demo get pods -o wide${NC}"
kubectl -n mtls-demo get pods -o wide
pause

clear
echo -e "${YELLOW}Step 2: Send traffic: it is transparently encrypted by ztunnel${NC}"
echo ""
echo -e "${CYAN}$ kubectl -n mtls-demo exec deploy/client -- curl -s -o /dev/null -w '%{http_code}' server:8080${NC}"
kubectl -n mtls-demo exec deploy/client -- curl -s -m 6 -o /dev/null -w '%{http_code}\n' server:8080 || echo "failed"
pause

clear
echo -e "${YELLOW}Step 3: New in 1.20: ztunnel metrics on every agent${NC}"
echo ""
echo -e "${CYAN}$ kubectl -n kube-system exec <cilium-pod> -- cilium-dbg metrics list | grep ztunnel${NC}"
echo ""
ztunnel_metrics | grep --color=always -E 'zds_connection_active|zds_enrollment_total|$'
echo ""
echo "  zds_connection_active   1 when the node's ztunnel proxy is connected"
echo "  zds_enrollment_total    cumulative enrollment events (a counter, not a pod count)"
echo "  *_failures_total        appear once a failure has occurred"
pause

clear
echo -e "${YELLOW}Step 4: Scale the server and watch enrollments grow${NC}"
echo ""
echo -e "${CYAN}$ kubectl -n mtls-demo scale deploy/server --replicas=3${NC}"
kubectl -n mtls-demo scale deploy/server --replicas=3
kubectl -n mtls-demo rollout status deploy/server --timeout=120s >/dev/null || true
sleep 3
echo ""
ztunnel_metrics | grep -E '^[^ ]|zds_enrollment_total' | grep --color=always -E 'zds_enrollment_total|$'
pause

clear
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Namespace-scoped, sidecarless mTLS with ztunnel${NC}"
echo -e "${GREEN}✅ Enrollment and connection health exported as Prometheus metrics${NC}"
echo -e "${GREEN}✅ Grafana dashboard: ztunnel-mtls-dashboard.json${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
