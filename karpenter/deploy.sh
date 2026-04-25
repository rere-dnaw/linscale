#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Installs Karpenter (CRDs + controller) from karpenter-provider-linode charts
# Usage: KARPENTER_TOKEN=... KARPENTER_CLUSTER_NAME=... ./deploy.sh
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NAMESPACE="${KARPENTER_NS:-kube-system}"
KARPENTER_TOKEN="${KARPENTER_TOKEN:?KARPENTER_TOKEN not set}"
CLUSTER_NAME="${KARPENTER_CLUSTER_NAME:?KARPENTER_CLUSTER_NAME not set}"
KARPENTER_CHART_DIR="${KARPENTER_PROVIDER_DIR}/charts"

BATCH_MAX_DURATION="${KARPENTER_BATCH_MAX_DURATION:-5m}"
BATCH_IDLE_DURATION="${KARPENTER_BATCH_IDLE_DURATION:-1m}"

echo "==> Installing Karpenter CRDs..."
helm upgrade --install karpenter-crd "$KARPENTER_CHART_DIR/karpenter-crd" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --wait

echo "==> Installing Karpenter..."
helm upgrade --install karpenter "$KARPENTER_CHART_DIR/karpenter" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --values "$SCRIPT_DIR/values.yaml" \
    --set settings.clusterName="$CLUSTER_NAME" \
    --set apiToken="$KARPENTER_TOKEN" \
    --set settings.batchMaxDuration="$BATCH_MAX_DURATION" \
    --set settings.batchIdleDuration="$BATCH_IDLE_DURATION" \
    --wait

echo "==> Waiting for Karpenter to be ready..."
kubectl wait --for=condition=ready pods -l app.kubernetes.io/name=karpenter -n "$NAMESPACE" --timeout=120s

echo "==> Karpenter deployed successfully!"