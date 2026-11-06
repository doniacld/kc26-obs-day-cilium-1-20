#!/usr/bin/env bash
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"
cd "$(dirname "$0")"

if ! kind get clusters 2>/dev/null | grep -qx kind; then
  echo "Creating kind cluster..."
  kind create cluster --config kind-config.yaml
fi

./ztunnel-keys.sh

echo "Installing Cilium ${CILIUM_VERSION} with Hubble, ztunnel and Prometheus metrics..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update cilium
helm repo update prometheus-community

helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --values values.yaml

echo "Waiting for Cilium to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
kubectl wait --for=condition=ready pod -l k8s-app=hubble-relay -n kube-system --timeout=300s

echo "Installing Prometheus and Grafana..."
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "${PROMETHEUS_STACK_VERSION:-92.20.0}" \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-values.yaml \
  --wait \
  --timeout 10m

kubectl wait --for=condition=Established crd/servicemonitors.monitoring.coreos.com --timeout=120s

echo "Configuring Prometheus to scrape Cilium agent metrics..."
helm upgrade cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --reuse-values \
  --values monitoring-cilium-values.yaml

kubectl -n monitoring create configmap ztunnel-mtls-dashboard \
  --from-file=ztunnel-mtls-dashboard.json="../02-ztunnel-metrics/ztunnel-mtls-dashboard.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring label configmap ztunnel-mtls-dashboard grafana_dashboard=1 --overwrite
kubectl -n monitoring create configmap cilium-config-drift-dashboard \
  --from-file=config-drift-dashboard.json="../03-more-observability/config-drift-dashboard.json" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring label configmap cilium-config-drift-dashboard grafana_dashboard=1 --overwrite
kubectl rollout status deployment/monitoring-grafana -n monitoring --timeout=300s

echo "Deploying the Star Wars demo app (demo 01)..."
kubectl apply -f "https://raw.githubusercontent.com/cilium/cilium/v${CILIUM_VERSION}/examples/minikube/http-sw-app.yaml"
kubectl rollout status deploy/deathstar --timeout=150s
kubectl wait --for=condition=Ready pod/tiefighter pod/xwing --timeout=120s

echo "Cilium ${CILIUM_VERSION} and monitoring installed successfully"
echo "Grafana dashboards: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
