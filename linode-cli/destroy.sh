#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes linode-cli Pod and credentials
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

NAMESPACE="${LINODE_CLI_NS:-default}"

echo "==> Deleting linode-cli pod..."
kubectl delete pod linode-cli -n "$NAMESPACE" 2>/dev/null || true

echo "==> Deleting linode-credentials secret..."
kubectl delete secret linode-credentials -n "$NAMESPACE" 2>/dev/null || true

echo "==> Done."
