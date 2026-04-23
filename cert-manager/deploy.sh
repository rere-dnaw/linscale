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
kubectl annotate namespace "$NAMESPACE" kubectl.kubernetes.io/last-applied-configuration='{}' --overwrite 2>/dev/null || true
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

echo "==> Installing Linode webhook..."
helm upgrade cert-manager-webhook-linode \
    --namespace "$NAMESPACE" \
    --install \
    --create-namespace \
    --version "$WEBHOOK_VERSION" \
    "$WEBHOOK_URL" || \
helm upgrade cert-manager-webhook-linode \
    --namespace "$NAMESPACE" \
    --install \
    --create-namespace \
    --set-string deployment.logLevel="" \
    --set-string image.tag=v0.4.1 \
    "$WEBHOOK_URL"

echo "==> Waiting for webhook provider to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=cert-manager-webhook-linode -n "$NAMESPACE" --timeout=120s || {
    echo "Checking webhook pod..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=cert-manager-webhook-linode 2>/dev/null || \
    kubectl get pods -n "$NAMESPACE" | grep webhook
}

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
envsubst < "$SCRIPT_DIR/cluster-issuer.yaml" | kubectl apply -f -

echo "==> ClusterIssuer deployed. Verify with: kubectl get clusterissuer letsencrypt-prod -o wide"
