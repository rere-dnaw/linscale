#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes cert-manager, Linode webhook, and namespace
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

NAMESPACE="cert-manager"

echo "==> Uninstalling cert-manager..."
helm uninstall cert-manager -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting namespace..."
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

echo "==> Done."
