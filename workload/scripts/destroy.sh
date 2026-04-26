#!/bin/bash
# -----------------------------------------------------------------------------
# Destroys workload with options to preserve or destroy PVC
# Usage: ./destroy.sh [--keep-pvc|--destroy-pvc]
# -----------------------------------------------------------------------------
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$WORKLOAD_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi
if [ -f "$WORKLOAD_DIR/.env" ]; then
    set -a
    source "$WORKLOAD_DIR/.env"
    set +a
fi

NAMESPACE="${WORKLOAD_NS:-workloads}"
WORKLOAD_NAME="${WORKLOAD_NAME:?WORKLOAD_NAME required}"

case "${1:-}" in
    --destroy-pvc)
        echo "==> Destroying workload WITH PVC data..."
        kubectl delete -n "$NAMESPACE" deployment "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" service "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" ingressroute "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" pvc "${WORKLOAD_NAME}-data" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" nodepool "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" nodeclass "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        echo "==> Removing firewall rules..."
        (cd "$REPO_ROOT/linode-firewall" && ./deploy.sh workload-remove "$WORKLOAD_NAME" "$NAMESPACE")
        rm -f "$WORKLOAD_DIR/${WORKLOAD_NAME}.last-run.yaml"
        ;;
    --keep-pvc|*)
        echo "==> Destroying workload keeping PVC data..."
        kubectl delete -n "$NAMESPACE" deployment "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" service "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" ingressroute "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" nodepool "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        kubectl delete -n "$NAMESPACE" nodeclass "$WORKLOAD_NAME" --wait=true 2>/dev/null || true
        echo "==> Removing firewall rules..."
        (cd "$REPO_ROOT/linode-firewall" && ./deploy.sh workload-remove "$WORKLOAD_NAME" "$NAMESPACE")
        echo "==> PVC preserved at $NAMESPACE/${WORKLOAD_NAME}-data"
        echo "    Run './deploy.sh --last-run' to re-deploy with existing PVC"
        ;;
esac
echo "==> Done"