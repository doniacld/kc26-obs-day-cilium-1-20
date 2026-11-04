#!/usr/bin/env bash
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"
cd "$(dirname "$0")"

if ! kind get clusters 2>/dev/null | grep -qx kind; then
  echo "Creating kind cluster..."
  kind create cluster --config kind-config.yaml
fi

echo "Installing Cilium ${CILIUM_VERSION} with Hubble, ztunnel and Prometheus metrics..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

if helm list -n kube-system | grep -q "^cilium"; then
  echo "Cilium already installed, skipping..."
else
  helm install cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    --values values.yaml
fi

echo "Waiting for Cilium to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
kubectl wait --for=condition=ready pod -l k8s-app=hubble-relay -n kube-system --timeout=300s

echo "Deploying the Star Wars demo app (demo 01)..."
kubectl apply -f "https://raw.githubusercontent.com/cilium/cilium/v${CILIUM_VERSION}/examples/minikube/http-sw-app.yaml"
kubectl rollout status deploy/deathstar --timeout=150s
kubectl wait --for=condition=Ready pod/tiefighter pod/xwing --timeout=120s

echo "Cilium ${CILIUM_VERSION} installed successfully"
