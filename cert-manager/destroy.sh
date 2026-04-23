#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes cert-manager, Linode webhook, and namespace
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="${CERT_MANAGER_NS:-cert-manager}"

PROTECTED_NAMESPACES="default kube-node-lease kube-public kube-system"
for protected in $PROTECTED_NAMESPACES; do
    if [ "$NAMESPACE" = "$protected" ]; then
        echo "ERROR: Cannot delete protected namespace '$NAMESPACE'"
        echo "This is a Kubernetes system namespace."
        exit 1
    fi
done

echo "==> Deleting ClusterIssuer..."
kubectl delete clusterissuer letsencrypt-prod 2>/dev/null || true

echo "==> Uninstalling Linode webhook DNS provider..."
helm uninstall cert-manager-webhook-linode -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting CertificateRequests matching traefik-dashboard-tls..."
for cr in $(kubectl get certificaterequests --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^traefik-dashboard-tls"); do
    ns=$(kubectl get certificaterequest "$cr" -o jsonpath='{.metadata.namespace}' 2>/dev/null)
    kubectl delete certificaterequest "$cr" -n "$ns" 2>/dev/null || true
done

echo "==> Uninstalling cert-manager..."
helm uninstall cert-manager -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

echo "==> Done."
