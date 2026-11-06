#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Settled screens in the full VHS recordings. Recheck times after changing a demo.
# Pass 1, 2, or 3 to export one demo; omit the argument to export all three.
demo=${1:-all}
case "$demo" in
  1|2|3|all) ;;
  *) echo "Usage: $0 [1|2|3|all]" >&2; exit 2 ;;
esac

stills=(
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 10.00 01-hubble-audit-policy-correlation/demo-01-intro.png'
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 24.00 01-hubble-audit-policy-correlation/demo-01-step-1-audit-mode.png'
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 34.00 01-hubble-audit-policy-correlation/demo-01-step-2-policies.png'
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 42.00 01-hubble-audit-policy-correlation/demo-01-step-3-traffic.png'
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 53.00 01-hubble-audit-policy-correlation/demo-01-step-4-audit-policy-correlation.png'
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 64.00 01-hubble-audit-policy-correlation/demo-01-step-5-allowed-flows.png'
  '1 01-hubble-audit-policy-correlation/demo-01-audit-correlation.gif 74.00 01-hubble-audit-policy-correlation/demo-01-summary.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 4.70 02-ztunnel-metrics/demo-02-intro.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 32.00 02-ztunnel-metrics/demo-02-step-1-enrollment.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 55.00 02-ztunnel-metrics/demo-02-step-2-traffic-comparison.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 66.00 02-ztunnel-metrics/demo-02-step-3-ztunnel-metrics.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 95.00 02-ztunnel-metrics/demo-02-step-4-scale.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 109.00 02-ztunnel-metrics/demo-02-step-5-grafana.png'
  '2 02-ztunnel-metrics/demo-02-ztunnel-metrics.gif 113.00 02-ztunnel-metrics/demo-02-summary.png'
  '3 03-more-observability/demo-03-config-drift.gif 11.00 03-more-observability/demo-03-step-1-baseline.png'
  '3 03-more-observability/demo-03-config-drift.gif 50.00 03-more-observability/demo-03-step-2-config-drift.png'
  '3 03-more-observability/demo-03-config-drift.gif 68.50 03-more-observability/demo-03-step-3-restored.png'
)

for still in "${stills[@]}"; do
  read -r still_demo recording timestamp output <<< "$still"
  [[ "$demo" == all || "$demo" == "$still_demo" ]] || continue
  temporary="${output%.png}.tmp.png"
  rm -f "$temporary"
  ffmpeg -y -loglevel error -i "$recording" -ss "$timestamp" -frames:v 1 "$temporary"
  if [[ ! -s "$temporary" ]]; then
    echo "No frame at ${timestamp}s in ${recording}." >&2
    exit 1
  fi
  mv "$temporary" "$output"
  printf '%s\n' "$output"
done
