#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

PROMETHEUS_FORWARD_LOG=$(mktemp)
prometheus_forward_pid=""
original_debug=""
restore_debug=false

cleanup() {
  if [[ "${restore_debug}" == true ]]; then
    echo "Restoring cilium-config debug=${original_debug}..."
    cilium config set debug "${original_debug}" --restart=false >/dev/null || true
  fi
  if [[ -n "${prometheus_forward_pid}" ]]; then
    kill "${prometheus_forward_pid}" 2>/dev/null || true
  fi
  rm -f "${PROMETHEUS_FORWARD_LOG}"
}
trap cleanup EXIT

pause() { echo ""; read -r -p "Press ENTER to continue..."; }

start_prometheus_forward() {
  local port
  kubectl -n monitoring port-forward --address 127.0.0.1 \
    svc/monitoring-kube-prometheus-prometheus :9090 \
    >"${PROMETHEUS_FORWARD_LOG}" 2>&1 &
  prometheus_forward_pid=$!

  for _ in {1..20}; do
    port=$(sed -nE 's/^Forwarding from 127\.0\.0\.1:([0-9]+) -> 9090$/\1/p' \
      "${PROMETHEUS_FORWARD_LOG}" | head -n 1)
    if [[ -n "${port}" ]] \
      && curl -fsS "http://127.0.0.1:${port}/-/ready" >/dev/null 2>&1; then
      PROMETHEUS_URL="http://127.0.0.1:${port}"
      return 0
    fi
    if ! kill -0 "${prometheus_forward_pid}" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  cat "${PROMETHEUS_FORWARD_LOG}" >&2
  echo "Prometheus port-forward did not become ready." >&2
  return 1
}

prometheus_query() {
  local query=$1
  curl -fsS -G --data-urlencode "query=${query}" \
    "${PROMETHEUS_URL}/api/v1/query"
}

query_has_result() {
  prometheus_query "$1" | jq -e '.status == "success" and (.data.result | length > 0)' >/dev/null
}

wait_for_metric() {
  local query=$1 description=$2
  echo "Waiting for Prometheus to scrape ${description}..."
  for _ in {1..45}; do
    if query_has_result "${query}"; then
      return 0
    fi
    sleep 2
  done
  echo "Prometheus did not observe ${description} within 90 seconds." >&2
  return 1
}

show_agent_values() {
  prometheus_query 'cilium_drift_checker_config_delta' \
    | jq -r '.data.result[] | "  \(.metric.node): \(.value[1]) unapplied keys"'
}

echo "DEMO 3: Cilium ConfigMap drift in Grafana"
echo "Open http://localhost:3000/d/cilium-config-drift/cilium-configmap-drift-detection"
echo "If needed: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"

original_debug=$(kubectl -n kube-system get cm cilium-config -o json \
  | jq -r '.data.debug // empty')
if [[ "${original_debug}" != true && "${original_debug}" != false ]]; then
  echo "Expected a true or false debug value in kube-system/cilium-config." >&2
  exit 1
fi
if [[ "${original_debug}" == true ]]; then
  drift_debug=false
else
  drift_debug=true
fi

start_prometheus_forward
if ! query_has_result 'max(cilium_drift_checker_config_delta) == 0'; then
  echo "Cilium already has config drift. Resolve that before running this demo." >&2
  show_agent_values
  exit 1
fi

echo ""
echo "Step 1: Baseline — every Cilium agent matches cilium-config"
show_agent_values
pause

echo ""
echo "Step 2: Change the desired debug value without restarting agents"
echo "$ cilium config set debug ${drift_debug} --restart=false"
restore_debug=true
cilium config set debug "${drift_debug}" --restart=false
wait_for_metric 'min(cilium_drift_checker_config_delta) > 0' 'config drift on every agent'
show_agent_values
echo "The Grafana stat panels now show unapplied configuration."
echo "The per-node graph rises above zero; keep this screen open while you inspect it."
pause

echo ""
echo "Step 3: Restore the original desired value"
echo "$ cilium config set debug ${original_debug} --restart=false"
cilium config set debug "${original_debug}" --restart=false
restore_debug=false
wait_for_metric 'max(cilium_drift_checker_config_delta) == 0' 'all agents back in sync'
show_agent_values
echo "Grafana returns to zero while the per-node graph retains the drift spike."
