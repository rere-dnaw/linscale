#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes Traefik, certificates, and namespace
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

NAMESPACE="${TRAEFIK_NS:-traefik}"

echo "==> Deleting IngressRoute..."
kubectl delete ingressroutes.traefik.io traefik-dashboard -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting middleware..."
kubectl delete middlewares.traefik.io traefik-dashboard-basicauth -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting CertificateRequests matching traefik-dashboard-tls*..."
for cr in $(kubectl get certificaterequests -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^traefik-dashboard-tls"); do
    kubectl delete certificaterequest "$cr" -n "$NAMESPACE" 2>/dev/null || true
done

echo "==> Deleting TLS certificate..."
kubectl delete certificate traefik-dashboard-tls -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting secrets..."
kubectl delete secret traefik-dashboard-auth -n "$NAMESPACE" 2>/dev/null || true
kubectl delete secret traefik-dashboard-tls -n "$NAMESPACE" 2>/dev/null || true
for secret in $(kubectl get secrets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^traefik-dashboard-tls-"); do
    kubectl delete secret "$secret" -n "$NAMESPACE" 2>/dev/null || true
done

echo "==> Uninstalling Traefik..."
helm uninstall traefik -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting RBAC..."
kubectl delete -f "https://raw.githubusercontent.com/traefik/traefik/v3.6/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml" 2>/dev/null || true

echo "==> Deleting CRDs..."
kubectl delete -f "https://raw.githubusercontent.com/traefik/traefik/v3.6/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml" 2>/dev/null || true

echo "==> Deleting namespace..."
kubectl delete namespace "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
