#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${LINODE_FIREWALL_NS:-kube-system}"

helm repo add linode-cfw https://linode.github.io/cloud-firewall-controller 2>/dev/null || true
helm repo update

helm upgrade --install cloud-firewall-crd linode-cfw/cloud-firewall-crd \
  --namespace "$NAMESPACE"

kubectl wait --for condition=established --timeout=60s crd/cloudfirewalls.networking.linode.com

helm upgrade --install cloud-firewall linode-cfw/cloud-firewall-controller \
  --namespace "$NAMESPACE" \
  --values "${SCRIPT_DIR}/values.yaml"
