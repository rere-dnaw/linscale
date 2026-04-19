#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Installs Traefik ingress controller with dashboard + TLS
# Usage: ./deploy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="traefik"
CHART_VERSION="39.0.8"

echo "==> Adding helm repos..."
helm repo add traefik https://helm.traefik.io/traefik 2>/dev/null || true
helm repo update

echo "==> Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Traefik helm chart..."
helm install traefik traefik/traefik \
    --version "$CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --values "$SCRIPT_DIR/values.yaml" \
    --wait

echo "==> Waiting for Traefik to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=traefik -n "$NAMESPACE" --timeout=120s

echo "==> Installing Traefik CRDs..."
CRDS_URL="https://raw.githubusercontent.com/traefik/traefik/v3.6/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml"
if kubectl create -f "$CRDS_URL" --save-config 2>/dev/null; then
    echo "    CRDs created with save-config"
else
    echo "    CRDs already exist, patching annotations..."
    for crd in ingressroutes.traefik.io ingressroutetcps.traefik.io ingressrouteudps.traefik.io middlewares.traefik.io middlewaretcps.traefik.io serverstransports.traefik.io serverstransporttcps.traefik.io tlsoptions.traefik.io tlsstores.traefik.io traefikservices.traefik.io; do
        kubectl annotate crd $crd kubectl.kubernetes.io/last-applied-configuration='{}' --overwrite 2>/dev/null || true
    done
fi
kubectl wait --for=condition=established crd/ingressroutes.traefik.io --timeout=30s

echo "==> Installing Traefik RBAC..."
kubectl apply -f "https://raw.githubusercontent.com/traefik/traefik/v3.6/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml"

echo "==> Creating dashboard middleware..."
kubectl apply -f "$SCRIPT_DIR/dashboard-middleware.yaml"

echo "==> Creating dashboard auth secret (admin:admin)..."
AUTH_HASH=$(kubectl run htpasswd-gen --image=httpd:alpine --rm -it --restart=Never -- \
  /bin/sh -c "printf 'admin\nadmin\n' | htpasswd -nBi admin" 2>/dev/null)
kubectl create secret generic traefik-dashboard-auth -n "$NAMESPACE" --from-literal=auth="$AUTH_HASH" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying dashboard IngressRoute..."
kubectl apply -f "$SCRIPT_DIR/ingress-route.yaml"

echo ""
echo "==> Traefik deployed successfully!"
echo ""
echo "==> Verify:"
echo "  kubectl get all -n $NAMESPACE"
echo "  kubectl get ingressroute -n $NAMESPACE"
echo "  kubectl get certificate"
echo ""
echo "==> DNS: Add A record for traefik.portal7.eu"
echo "    Then access dashboard at https://traefik.portal7.eu/dashboard/"
echo ""
echo "==> WARNING: Default password 'admin:admin' is set. Update it before production use!"
echo "    See GUIDE.md section 'Updating Dashboard Password' for instructions."
