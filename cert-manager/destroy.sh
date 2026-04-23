#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes cert-manager, Linode webhook, and namespace
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="${CERT_MANAGER_NS:-cert-manager}"

echo "==> Deleting ClusterIssuer..."
kubectl delete clusterissuer letsencrypt-prod 2>/dev/null || true

echo "==> Uninstalling Linode webhook DNS provider..."
helm uninstall cert-manager-webhook-linode -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting CertificateRequests matching traefik-dashboard-tls..."
for cr in $(kubectl get certificaterequests --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^traefik-dashboard-tls"); do
    ns=$(kubectl get certificaterequest "$cr" -o jsonpath='{.metadata.namespace}' 2>/dev/null)
    kubectl delete certificaterequest "$cr" -n "$ns" 2>/dev/null || true
done

echo "==> Deleting RBAC..."
kubectl delete -f "$SCRIPT_DIR/rbac.yaml" 2>/dev/null || true

echo "==> Uninstalling cert-manager..."
helm uninstall cert-manager -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

echo "==> Done."
