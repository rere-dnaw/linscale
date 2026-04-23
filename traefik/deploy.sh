#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Installs Traefik ingress controller (fully Helm-based)
# Usage: TRAEFIK_USER=admin TRAEFIK_PASSWORD=yourpassword ./deploy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="${TRAEFIK_NS:-traefik}"
CHART_VERSION="39.0.8"
TRAEFIK_USER="${TRAEFIK_USER:?TRAEFIK_USER not set in .env}"
TRAEFIK_PASSWORD="${TRAEFIK_PASSWORD:?TRAEFIK_PASSWORD not set in .env}"

echo "==> Adding helm repos..."
helm repo add traefik https://helm.traefik.io/traefik 2>/dev/null || true
helm repo update

echo "==> Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade traefik traefik/traefik \
    --install \
    --version "$CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --values "$SCRIPT_DIR/values.yaml" \
    --set-string extraObjects[0].stringData.username="$TRAEFIK_USER" \
    --set-string extraObjects[0].stringData.password="$TRAEFIK_PASSWORD" \
    --wait

echo "==> Waiting for Traefik to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=traefik -n "$NAMESPACE" --timeout=120s

echo ""
echo "==> Traefik deployed successfully!"
echo ""
echo "==> Verify:"
echo "  kubectl get all -n $NAMESPACE"
echo "  kubectl get gateways -n $NAMESPACE"
echo "  kubectl get httproutes -n $NAMESPACE"
echo "  kubectl get middlewares -n $NAMESPACE"
echo "  kubectl get certificates -n $NAMESPACE"
echo ""
echo "==> DNS: Add A record for traefik.$TRAEFIK_DOMAIN"
echo ""
echo "==> Dashboard user name: $TRAEFIK_USER"
