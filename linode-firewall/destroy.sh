#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes Linode Cloud Firewall controller and CRDs
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

NAMESPACE="${LINODE_FIREWALL_NS:-kube-system}"

PROTECTED_NAMESPACES="default kube-node-lease kube-public kube-system"
for protected in $PROTECTED_NAMESPACES; do
    if [ "$NAMESPACE" = "$protected" ]; then
        echo "ERROR: Cannot delete protected namespace '$NAMESPACE'"
        echo "This is a Kubernetes system namespace."
        exit 1
    fi
done

echo "==> Uninstalling Cloud Firewall controller..."
helm uninstall cloud-firewall -n "$NAMESPACE" 2>/dev/null || true

echo "==> Uninstalling Cloud Firewall CRD..."
helm uninstall cloud-firewall-crd -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting CRDs..."
kubectl delete crd cloudfirewalls.networking.linode.com 2>/dev/null || true

echo "==> Done."
