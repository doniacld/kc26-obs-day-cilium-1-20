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

grafana_pid=''
grafana_log=''
grafana_port=''
server_scaled=false

start_grafana_forward() {
  local attempt
  grafana_log=$(mktemp)
  kubectl -n monitoring port-forward --address 127.0.0.1 svc/monitoring-grafana :80 \
    >"${grafana_log}" 2>&1 &
  grafana_pid=$!
  for ((attempt=0; attempt<40; attempt++)); do
    grafana_port=$(sed -nE 's/^Forwarding from 127\.0\.0\.1:([0-9]+) -> .*/\1/p' "${grafana_log}" | head -n 1)
    [[ -n "${grafana_port}" ]] && return 0
    if ! kill -0 "${grafana_pid}" 2>/dev/null; then
      cat "${grafana_log}" >&2
      return 1
    fi
    sleep 0.25
  done
  cat "${grafana_log}" >&2
  echo "Grafana port-forward did not become ready." >&2
  return 1
}

cleanup() {
  local status=$? attempt count
  trap - EXIT
  if [[ -n "${grafana_pid}" ]]; then
    kill "${grafana_pid}" 2>/dev/null || true
    wait "${grafana_pid}" 2>/dev/null || true
  fi
  [[ -z "${grafana_log}" ]] || rm -f "${grafana_log}"
  if [[ "${server_scaled}" == true ]]; then
    if kubectl -n mtls-demo scale deploy/server --replicas=1 >/dev/null; then
      for ((attempt=0; attempt<30; attempt++)); do
        count=$(kubectl -n mtls-demo get pods -l app=server -o json | jq '.items | length') || break
        [[ "${count}" == 1 ]] && break
        sleep 2
      done
      if [[ "${count:-0}" != 1 ]]; then
        echo "The server was scaled to one replica, but extra Pods have not finished terminating." >&2
        status=1
      fi
    else
      echo "Could not restore the mTLS server to one replica." >&2
      status=1
    fi
  fi
  exit "${status}"
}
trap cleanup EXIT

# Off screen: make sure both demo workloads are ready before presenting them.
kubectl apply -f plain-demo.yaml >/dev/null
if [[ "$(kubectl get namespace plain-demo -o json | jq -r '.metadata.labels["io.cilium/mtls-enabled"] // empty')" == true ]]; then
  kubectl label namespace plain-demo io.cilium/mtls-enabled- >/dev/null
  sleep 5
fi
kubectl apply -f mtls-demo.yaml >/dev/null
kubectl -n plain-demo rollout status deploy/server deploy/client --timeout=120s >/dev/null
kubectl -n mtls-demo rollout status deploy/server deploy/client --timeout=120s >/dev/null

clear
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}DEMO 2: ztunnel mTLS Metrics${NC}"
echo -e "${WHITE}════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${WHITE}ztunnel encrypts TCP traffic between pods in the enrolled namespace.${NC}"
echo -e "${WHITE}Cilium 1.20 exports enrollment and connection-health metrics on each agent.${NC}"
pause

clear
echo -e "${GREEN}Step 1: Compare unenrolled and enrolled namespaces${NC}"
echo ""
echo -e "${CYAN}$ kubectl get ns plain-demo mtls-demo --show-labels${NC}"
kubectl get ns plain-demo mtls-demo --show-labels
echo ""
echo -e "${CYAN}$ kubectl -n plain-demo get pods -o wide${NC}"
kubectl -n plain-demo get pods -o wide
echo ""
echo -e "${CYAN}$ kubectl -n mtls-demo get pods -o wide${NC}"
kubectl -n mtls-demo get pods -o wide
pause

clear
echo -e "${YELLOW}Step 2: Compare Hubble flows and the bytes on the pod interface${NC}"
echo ""
echo -e "${WHITE}Both clients send the same marked HTTP request directly to their server Pod IP.${NC}"
echo -e "${WHITE}Hubble identifies each client/server flow; a capture checks whether the marked${NC}"
echo -e "${WHITE}HTTP header is readable on each client's eth0.${NC}"
echo ""
bash capture-comparison.sh
pause

clear
echo -e "${YELLOW}Step 3: New in 1.20: ztunnel metrics on every agent${NC}"
echo ""
echo -e "${CYAN}$ kubectl -n kube-system exec <cilium-pod> -- cilium-dbg metrics list | grep ztunnel${NC}"
echo ""
ztunnel_metrics | grep --color=always -E 'zds_connection_active|zds_enrollment_total|$'
echo ""
echo -e "${WHITE}  zds_connection_active   1 when the node's ztunnel proxy is connected${NC}"
echo -e "${WHITE}  zds_enrollment_total    cumulative enrollment events (a counter, not a pod count)${NC}"
echo -e "${WHITE}  *_failures_total        appear once a failure has occurred${NC}"
pause

clear
echo -e "${YELLOW}Step 4: Scale the server and watch enrollments grow${NC}"
echo ""
echo -e "${CYAN}$ kubectl -n mtls-demo scale deploy/server --replicas=3${NC}"
server_scaled=true
kubectl -n mtls-demo scale deploy/server --replicas=3
kubectl -n mtls-demo rollout status deploy/server --timeout=120s >/dev/null || true
sleep 3
echo ""
ztunnel_metrics | grep -E '^[^ ]|zds_enrollment_total' | grep --color=always -E 'zds_enrollment_total|$'
pause

clear
echo -e "${YELLOW}Step 5: Inspect the ztunnel metrics in Grafana${NC}"
echo ""
start_grafana_forward
grafana_url="http://localhost:${grafana_port}/d/ztunnel-mtls/cilium-ztunnel-native-mtls"
echo -e "${WHITE}Look at the connection state and enrollment panels after scaling the server.${NC}"
echo -e "${WHITE}Enrollment events are cumulative; the dashboard does not count live protected Pods.${NC}"
echo -e "${CYAN}${grafana_url}${NC}"
if command -v open >/dev/null 2>&1; then
  echo -e "${CYAN}$ open '${grafana_url}'${NC}"
  open "${grafana_url}" >/dev/null 2>&1 || true
elif command -v xdg-open >/dev/null 2>&1; then
  echo -e "${CYAN}$ xdg-open '${grafana_url}'${NC}"
  xdg-open "${grafana_url}" >/dev/null 2>&1 || true
fi
echo -e "${WHITE}The link stays active until you press ENTER to finish the demo.${NC}"
pause

clear
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Namespace-scoped, sidecarless mTLS with ztunnel${NC}"
echo -e "${GREEN}✅ Enrollment and connection health exported as Prometheus metrics${NC}"
echo -e "${GREEN}✅ Grafana dashboard: ztunnel-mtls-dashboard.json${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
