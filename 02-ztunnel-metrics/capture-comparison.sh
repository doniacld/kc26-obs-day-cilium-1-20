#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[1;32m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

comment() { printf '%b%s%b\n' "${WHITE}" "$1" "${NC}"; }
command_line() { printf '%b$ %s%b\n' "${CYAN}" "$1" "${NC}"; }

CAPTURE_DIR=$(mktemp -d)
PLAIN_PCAP="/tmp/demo2-plain-$$.pcap"
MTLS_PCAP="/tmp/demo2-mtls-$$.pcap"
PROBE_HEADER='X-Demo-Probe: visible-in-plaintext'
plain_capture_started=false
mtls_capture_started=false

cleanup_captures() {
  if [[ "${plain_capture_started}" == true ]]; then
    kubectl -n plain-demo exec deploy/client -- rm -f "${PLAIN_PCAP}" >/dev/null 2>&1 || true
  fi
  if [[ "${mtls_capture_started}" == true ]]; then
    kubectl -n mtls-demo exec deploy/client -- rm -f "${MTLS_PCAP}" >/dev/null 2>&1 || true
  fi
  rm -rf "${CAPTURE_DIR}"
}
trap cleanup_captures EXIT

ready_server_ip() {
  local namespace=$1
  kubectl -n "${namespace}" get endpointslices -l kubernetes.io/service-name=server -o json \
    | jq -r '[.items[].endpoints[] | select(.conditions.ready != false and .conditions.terminating != true) | .addresses[]][0] // empty'
}

show_hubble_flow() {
  local namespace=$1 port=$2 since=$3 attempt
  local flow_log="${CAPTURE_DIR}/${namespace}-hubble.log"
  local error_log="${CAPTURE_DIR}/${namespace}-hubble-error.log"

  comment "Hubble client-to-server flow (one data packet):"
  command_line "hubble observe --port-forward --port-forward-port 0 --since ${since} --from-pod ${namespace}/client --to-pod ${namespace}/server --to-port ${port} --output compact"
  for attempt in 1 2 3; do
    if ! hubble observe --port-forward --port-forward-port 0 --since "${since}" \
      --from-pod "${namespace}/client" --to-pod "${namespace}/server" \
      --to-port "${port}" --output compact >"${flow_log}" 2>"${error_log}"; then
      cat "${error_log}" >&2
      return 1
    fi
    if grep -m 1 'TCP Flags: ACK, PSH' "${flow_log}"; then
      return 0
    fi
    if (( attempt < 3 )); then
      comment "Waiting for Hubble to report the flow..."
      sleep 4
    fi
  done
  cat "${flow_log}" >&2
  echo "Hubble did not report a ${namespace} data flow to port ${port}." >&2
  return 1
}

show_probe_search() {
  local namespace=$1 pcap=$2
  command_line "kubectl -n ${namespace} exec deploy/client -- tcpdump -A -nn -r ${pcap} 2>/dev/null | grep -F '${PROBE_HEADER}'"
  if kubectl -n "${namespace}" exec deploy/client -- tcpdump -A -nn -r "${pcap}" 2>/dev/null \
    | grep -F "${PROBE_HEADER}"; then
    [[ "${namespace}" == plain-demo ]] || {
      echo "The marked HTTP header was visible on eth0; encryption is not demonstrated." >&2
      return 1
    }
  else
    [[ "${namespace}" == mtls-demo ]] || {
      echo "The plaintext capture did not show the marked HTTP header." >&2
      return 1
    }
    echo "(no match)"
  fi
}

capture_request() {
  local namespace=$1 pcap=$2 server_ip client_pod capture_pid
  server_ip=$(ready_server_ip "${namespace}")
  client_pod=$(kubectl -n "${namespace}" get pod -l app=client -o jsonpath='{.items[0].metadata.name}')
  if [[ -z "${server_ip}" || -z "${client_pod}" ]]; then
    echo "Could not find a ready client and server in ${namespace}." >&2
    return 1
  fi

  if [[ "${namespace}" == plain-demo ]]; then
    plain_capture_started=true
  else
    mtls_capture_started=true
  fi

  comment "Capturing ${namespace}/${client_pod} on eth0; server Pod IP: ${server_ip}"
  capture_since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  kubectl -n "${namespace}" exec "${client_pod}" -- \
    timeout -s INT 8 tcpdump -p --immediate-mode -U -nn -s 0 -i eth0 -c 24 \
      -w "${pcap}" "host ${server_ip} and tcp" \
    >"${CAPTURE_DIR}/${namespace}-tcpdump.log" 2>&1 &
  capture_pid=$!
  sleep 2

  command_line "kubectl -n ${namespace} exec ${client_pod} -- curl -fsS -m 6 -o /dev/null -w 'HTTP %{http_code}\\n' -H '${PROBE_HEADER}' http://${server_ip}:8080/"
  if ! kubectl -n "${namespace}" exec "${client_pod}" -- \
    curl -fsS -m 6 -o /dev/null -w 'HTTP %{http_code}\n' \
      -H "${PROBE_HEADER}" "http://${server_ip}:8080/"; then
    wait "${capture_pid}" || true
    echo "The ${namespace} request failed." >&2
    return 1
  fi
  wait "${capture_pid}" || true
  if ! kubectl -n "${namespace}" exec "${client_pod}" -- test -s "${pcap}"; then
    cat "${CAPTURE_DIR}/${namespace}-tcpdump.log" >&2
    echo "The ${namespace} capture failed." >&2
    return 1
  fi
}

printf '%b%s%b\n' "${GREEN}" 'Unenrolled namespace: marked HTTP header visible on eth0' "${NC}"
capture_request plain-demo "${PLAIN_PCAP}"
kubectl -n plain-demo exec deploy/client -- tcpdump -A -nn -r "${PLAIN_PCAP}" \
  >"${CAPTURE_DIR}/plain-ascii.log" 2>"${CAPTURE_DIR}/plain-read.log"
if ! grep -Fq 'GET / HTTP/1.1' "${CAPTURE_DIR}/plain-ascii.log"; then
  echo "The plaintext capture did not show an HTTP request." >&2
  exit 1
fi
show_hubble_flow plain-demo 8080 "${capture_since}"
show_probe_search plain-demo "${PLAIN_PCAP}"

echo ""
printf '%b%s%b\n' "${GREEN}" 'Enrolled namespace: marked HTTP header not visible on eth0' "${NC}"
capture_request mtls-demo "${MTLS_PCAP}"
kubectl -n mtls-demo exec deploy/client -- tcpdump -nn -r "${MTLS_PCAP}" \
  >"${CAPTURE_DIR}/mtls-packets.log" 2>"${CAPTURE_DIR}/mtls-read.log"
if ! grep -q -E 'IP .*\.15008' "${CAPTURE_DIR}/mtls-packets.log"; then
  echo "The enrolled capture did not show traffic on port 15008." >&2
  exit 1
fi
show_hubble_flow mtls-demo 15008 "${capture_since}"
show_probe_search mtls-demo "${MTLS_PCAP}"
