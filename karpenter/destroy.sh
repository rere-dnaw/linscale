#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Removes Karpenter and CRDs
# Usage: ./destroy.sh
# -----------------------------------------------------------------------------

set -e

NAMESPACE="${KARPENTER_NS:-kube-system}"

echo "==> Uninstalling Karpenter..."
helm uninstall karpenter -n "$NAMESPACE" 2>/dev/null || true

echo "==> Uninstalling Karpenter CRDs..."
helm uninstall karpenter-crd -n "$NAMESPACE" 2>/dev/null || true

echo "==> Done."