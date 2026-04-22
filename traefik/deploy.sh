#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Installs Traefik ingress controller (fully Helm-based)
# Usage: TRAEFIK_USER=admin TRAEFIK_PASSWORD=yourpassword ./deploy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="traefik"
CHART_VERSION="39.0.8"
TRAEFIK_USER="${TRAEFIK_USER:-admin665}"
TRAEFIK_PASSWORD="${TRAEFIK_PASSWORD:-adminLB123}"

echo "==> Adding helm repos..."
helm repo add traefik https://helm.traefik.io/traefik 2>/dev/null || true
helm repo update

echo "==> Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Traefik helm chart..."
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
echo ""

echo "  kubectl get certificates -n $NAMESPACE"
echo ""
echo "==> Prerequisites (if not already installed):"
echo "  1. Gateway API CRDs:"
echo "     kubectl apply -f https://raw.githubusercontent.com/kubernetes/gateway-api/master/deploy/static/gateway.yaml"
echo "  2. cert-manager with letsencrypt-prod ClusterIssuer must be present"
echo ""
echo "==> DNS: Add A record for traefik.portal7.eu"
echo ""
echo "==> Dashboard credentials: $TRAEFIK_USER / $TRAEFIK_PASSWORD"
