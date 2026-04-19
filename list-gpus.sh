#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${SKYNET_NAMESPACE:-default}"

[ -f "${SCRIPT_DIR}/.env" ] && set -a && source "${SCRIPT_DIR}/.env" && set +a

LINODE_CLI_NAMESPACE="${SKYNET_NAMESPACE:-default}"

echo "=== Querying Linode GPU Instance Types ==="

# Ensure pod is running
if ! kubectl get pod linode-cli -n "$LINODE_CLI_NAMESPACE" &>/dev/null; then
    echo "Deploying linode-cli pod..."
    envsubst < "${SCRIPT_DIR}/linode-cli-secret.yaml.tpl" | kubectl apply -f -
    envsubst < "${SCRIPT_DIR}/linode-cli-pod.yaml" | kubectl apply -f -
    echo "Waiting for pod..."
    kubectl wait --for=condition=Ready pod/linode-cli -n "$LINODE_CLI_NAMESPACE" --timeout=60s
fi

# Query GPU types
echo ""
echo "GPU Instance Types:"
kubectl exec linode-cli -n "$LINODE_CLI_NAMESPACE" -- \
    linode-cli linodes types \
    --format "id,label,vcpus,memory,gpus,price.monthly,price.hourly" \
    --no-headers 2>/dev/null | grep gpu || echo "No GPU types found"

echo ""
echo "=== Region Availability ==="
kubectl exec linode-cli -n "$LINODE_CLI_NAMESPACE" -- \
    linode-cli regions availability \
    --format "id,availability" \
    --json 2>/dev/null | jq -r '.[] | select(.availability | length > 0) | "\(.id): \(.availability | join(", "))"' | head -10

echo ""
echo "Note: gpu-8gb = 1x RTX 4000 Ada (~$150/mo)"
echo "      gpu-16gb = 1x RTX 4000 Ada (~$250/mo)"
