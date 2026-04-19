#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Installs cert-manager with Linode DNS-01 challenge solver
# Usage: ./cert-manager-setup.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="cert-manager"
CHART_VERSION="1.20.2"

echo "==> Adding helm repos..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

echo "==> Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing cert-manager helm chart..."
helm upgrade \
    cert-manager \
    jetstack/cert-manager \
    --install \
    --version "v$CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --values "$SCRIPT_DIR/values.yaml"

echo "==> Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/instance=cert-manager -n "$NAMESPACE" --timeout=120s

echo "==> Applying ClusterIssuer for Let's Encrypt..."
kubectl apply -f "$SCRIPT_DIR/issuers/letsencrypt-prod.yaml"

echo ""
echo "After creating the secret, verify the ClusterIssuer:"
echo "  kubectl describe clusterissuer letsencrypt-prod"
echo ""
