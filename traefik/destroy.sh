#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes Traefik, certificates, and namespace
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

NAMESPACE="traefik"

echo "==> Deleting IngressRoute..."
kubectl delete ingressroute traefik-dashboard -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting middleware..."
kubectl delete middleware traefik-dashboard-basicauth -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting secret..."
kubectl delete secret traefik-dashboard-auth -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting certificates..."
kubectl delete certificate traefik-dashboard-tls -n "$NAMESPACE" 2>/dev/null || true

echo "==> Uninstalling Traefik..."
helm uninstall traefik -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting RBAC..."
kubectl delete -f "https://raw.githubusercontent.com/traefik/traefik/v3.6/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml" 2>/dev/null || true

echo "==> Deleting CRDs..."
kubectl delete -f "https://raw.githubusercontent.com/traefik/traefik/v3.6/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml" 2>/dev/null || true

echo "==> Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

echo "==> Done."
