#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Creates linode-cli Pod with credentials from environment
# Usage: LINODE_TOKEN=yourtoken LINODE_CLI_NS=default ./deploy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${LINODE_CLI_NS:?LINODE_CLI_NS not set in .env}"
LINODE_TOKEN="${LINODE_TOKEN:-}"

if [ -z "$LINODE_TOKEN" ]; then
    echo "Error: LINODE_TOKEN environment variable is required"
    exit 1
fi

echo "==> Creating namespace if needed..."
kubectl annotate namespace "$NAMESPACE" kubectl.kubernetes.io/last-applied-configuration='{}' --overwrite 2>/dev/null || true
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying credentials secret..."
LINODE_CLI_TOKEN="$LINODE_TOKEN" envsubst < "$SCRIPT_DIR/linode-cli-secret.yaml.tpl" | kubectl apply -f -

echo "==> Applying linode-cli pod..."
envsubst < "$SCRIPT_DIR/linode-cli-pod.yaml" | kubectl apply -f -

echo "==> Waiting for linode-cli pod..."
kubectl wait --for=condition=ready pod/linode-cli -n "$NAMESPACE" --timeout=60s

echo "==> linode-cli deployed successfully!"
echo ""
echo "==> Verify:"
echo "  kubectl exec -it -n $NAMESPACE linode-cli -- linode-cli linodes list"
echo ""
