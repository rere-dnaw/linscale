#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Installs cert-manager with Linode DNS-01 challenge solver
# Usage: ./deploy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="${CERT_MANAGER_NS:-cert-manager}"
CHART_VERSION="1.20.2"
WEBHOOK_VERSION="v0.4.1"
WEBHOOK_URL="https://github.com/linode/cert-manager-webhook-linode/releases/download/${WEBHOOK_VERSION}/cert-manager-webhook-linode-${WEBHOOK_VERSION}.tgz"

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
    --values "$SCRIPT_DIR/values.yaml" \
    --wait

echo "==> Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/instance=cert-manager -n "$NAMESPACE" --timeout=120s

echo "Installing from $WEBHOOK_URL..."
helm upgrade cert-manager-webhook-linode \
    --namespace "$NAMESPACE" \
    --set-string deployment.logLevel="" \
    --set-string image.tag=v0.4.1 \
    "$WEBHOOK_URL"

echo "==> Waiting for webhook provider to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=cert-manager-webhook-linode -n "$NAMESPACE" --timeout=120s || {
    echo "Checking webhook pod..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=cert-manager-webhook-linode 2>/dev/null || \
    kubectl get pods -n "$NAMESPACE" | grep webhook
}

echo "==> Applying RBAC for Linode DNS..."
kubectl apply -f "$SCRIPT_DIR/rbac.yaml"

echo "==> Checking Linode token secret..."
if ! kubectl get secret linode-credentials -n "$NAMESPACE" 2>/dev/null; then
    if [ -n "$CERT_MANAGER_TOKEN" ]; then
        echo "==> Creating linode-credentials secret from CERT_MANAGER_TOKEN..."
        kubectl create secret generic linode-credentials \
            -n "$NAMESPACE" \
            --from-literal=token="$CERT_MANAGER_TOKEN"
    else
        echo "ERROR: linode-credentials not found and CERT_MANAGER_TOKEN not set."
        echo "See secret-guide.md for setup instructions."
        exit 1
    fi
fi

echo "==> Applying ClusterIssuer..."
TEMP_ISSUER=$(mktemp)
envsubst < "$SCRIPT_DIR/issuers/letsencrypt-prod.yaml" > "$TEMP_ISSUER"
kubectl apply -f "$TEMP_ISSUER"
rm -f "$TEMP_ISSUER"

echo "==> Waiting for ClusterIssuer..."
kubectl wait --for=condition=ready clusterissuer/letsencrypt-prod --timeout=120s || {
    echo "WARNING: ClusterIssuer not ready. Check:"
    echo "  kubectl describe clusterissuer letsencrypt-prod"
}
