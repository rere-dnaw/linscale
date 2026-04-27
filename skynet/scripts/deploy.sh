#!/bin/bash
# -----------------------------------------------------------------------------
# Deploys skynet workload with Karpenter nodepool, TLS, PVC, GPU support
# Usage: ./deploy.sh [--last-run]
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

if [ "${1:-}" = "--last-run" ]; then
    LAST_RUN_FILE="$WORKLOAD_DIR/${WORKLOAD_NAME}.last-run.yaml"
    if [ -f "$LAST_RUN_FILE" ]; then
        echo "==> Loading last run config from $LAST_RUN_FILE"
        WORKLOAD_NAME=$(grep -E '^WORKLOAD_NAME:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        WORKLOAD_IMAGE=$(grep -E '^WORKLOAD_IMAGE:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        WORKLOAD_INSTANCE_TYPE=$(grep -E '^WORKLOAD_INSTANCE_TYPE:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        PVC_ENABLED=$(grep -E '^PVC_ENABLED:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
    else
        echo "Warning: Last run file not found, using .env config"
    fi
fi

NAMESPACE="${WORKLOAD_NS:-workloads}"
WORKLOAD_NAME="${WORKLOAD_NAME:?WORKLOAD_NAME required}"
IMAGE="${WORKLOAD_IMAGE:-nginx:latest}"
WEB_PORT="${WEB_PORT:-8000}"
ENABLE_TLS="${ENABLE_TLS:-true}"
PVC_ENABLED="${PVC_ENABLED:-true}"

export WORKLOAD_NS NAMESPACE WORKLOAD_NAME IMAGE WEB_PORT
export REPLICAS="$(printf '%d' ${REPLICAS:-1})"
export CPU_REQUEST="${CPU_REQUEST:-2}" MEMORY_REQUEST="${MEMORY_REQUEST:-8Gi}"
export CPU_LIMIT="${CPU_LIMIT:-4}" MEMORY_LIMIT="${MEMORY_LIMIT:-16Gi}"
export WEB_HOST PVC_SIZE WORKLOAD_INSTANCE_TYPE
export EXTRA_PORTS_SVC EXTRA_PORTS_FW

echo "==> Validating prerequisites..."
kubectl cluster-info 2>/dev/null || { echo "Error: No cluster connection"; exit 1; }
kubectl get pod linode-cli -n "${LINODE_CLI_NS:-default}" 2>/dev/null || { echo "Error: linode-cli not running"; exit 1; }
kubectl get pods -n "${LINODE_FIREWALL_NS:-kube-system}" -l app.kubernetes.io/name=cloud-firewall-controller 2>/dev/null | grep -q Running || { echo "Error: cloud-firewall-controller not ready"; exit 1; }

echo "==> Checking NVIDIA GPU Operator..."
if ! kubectl get pods -n gpu-operator 2>/dev/null | grep -q Running; then
    echo "==> GPU Operator not found, installing..."
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true
    helm repo update 2>/dev/null || true
    helm install --wait --generate-name \
        -n gpu-operator --create-namespace \
        nvidia/gpu-operator \
        --version=v25.3 2>/dev/null || true
    echo "==> Waiting for GPU Operator to be ready..."
    sleep 30
fi

echo "==> Verifying GPU support on nodes..."
GPU_NODES=$(kubectl get nodes -o json | jq '[.items[] | select(.status.capacity."nvidia.com/gpu")] | length' 2>/dev/null || echo "0")
if [ "$GPU_NODES" = "0" ]; then
    echo "Warning: No GPU nodes detected. Ensure GPU operator is running and nodes have GPUs."
fi

if [ -z "$WORKLOAD_INSTANCE_TYPE" ]; then
    echo "==> Selecting instance type..."
    export LINODE_CLI_NS="${LINODE_CLI_NS:-default}"
    WORKLOAD_INSTANCE_TYPE=$("$SCRIPT_DIR/select-instance.sh")
    echo "==> Selected: $WORKLOAD_INSTANCE_TYPE"
fi

echo "==> Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

EXTRA_PORTS_SVC=""
EXTRA_PORTS_FW=""
if [ -n "$EXTRA_PORTS" ]; then
    echo "==> Processing extra ports: $EXTRA_PORTS"
    IFS=',' read -ra PORTS <<< "$EXTRA_PORTS"
    for p in "${PORTS[@]}"; do
        name="${p%%:*}"
        port="${p##*:}"
        rest="${p%:${port}}"
        protocol="${rest##*:}"
        [ "$protocol" = "$port" ] && protocol="TCP"
        [ "$protocol" = "TCP" ] || [ "$protocol" = "UDP" ] || protocol="TCP"

        EXTRA_PORTS_SVC="${EXTRA_PORTS_SVC}
    - name: ${name}
      port: ${port}
      targetPort: ${port}
      protocol: ${protocol}"

        EXTRA_PORTS_FW="${EXTRA_PORTS_FW}
    - label: \"allow-${name}\"
      action: ACCEPT
      description: \"${name} access for ${WORKLOAD_NAME}\"
      protocol: ${protocol}
      ports: \"${port}\"
      addresses:
        ipv4:
        - 0.0.0.0/0"
    done
fi
export EXTRA_PORTS_SVC EXTRA_PORTS_FW

cat > "$WORKLOAD_DIR/${WORKLOAD_NAME}.last-run.yaml" <<EOF
WORKLOAD_NAME: ${WORKLOAD_NAME}
WORKLOAD_NS: ${NAMESPACE}
WORKLOAD_IMAGE: ${IMAGE}
WORKLOAD_INSTANCE_TYPE: ${WORKLOAD_INSTANCE_TYPE}
WEB_HOST: ${WEB_HOST}
EXTRA_PORTS: ${EXTRA_PORTS}
PVC_ENABLED: ${PVC_ENABLED}
PVC_SIZE: ${PVC_SIZE}
EOF

echo "==> Creating Karpenter nodepool..."
CPU_LIMIT_CORE=$(echo "$CPU_LIMIT" | grep -oE '[0-9]+')
export CPU_LIMIT_CORE
envsubst < "$WORKLOAD_DIR/templates/nodepool.yaml.tpl" | kubectl apply -f -

echo "==> Deploying skynet workload..."
envsubst < "$WORKLOAD_DIR/templates/deployment.yaml.tpl" | kubectl apply -f -

echo "==> Creating service..."
envsubst < "$WORKLOAD_DIR/templates/service.yaml.tpl" | kubectl apply -f -

if [ "$ENABLE_TLS" = "true" ]; then
    echo "==> Configuring TLS..."
    envsubst < "$WORKLOAD_DIR/templates/ingress.yaml.tpl" | kubectl apply -f -
    envsubst < "$WORKLOAD_DIR/templates/wildcard-cert.yaml.tpl" | kubectl apply -f -
fi

if [ "$PVC_ENABLED" = "true" ]; then
    echo "==> Creating PVCs..."
    envsubst < "$WORKLOAD_DIR/templates/pvc.yaml.tpl" | kubectl apply -f -
fi

echo "==> Creating firewall rules..."
export WORKLOAD_NAME NAMESPACE EXTRA_PORTS_FW
cd "$REPO_ROOT/linode-firewall" && ./deploy.sh workload-apply "$WORKLOAD_NAME" "$NAMESPACE" "$EXTRA_PORTS_FW"

echo "==> Waiting for deployment..."
kubectl wait --for=condition=available deployment/${WORKLOAD_NAME} -n "$NAMESPACE" --timeout=900s || true

echo ""
echo "========================================"
echo "Deployment complete!"
echo "========================================"
echo "Workload: $WORKLOAD_NAME"
echo "Namespace: $NAMESPACE"
echo "Instance: $WORKLOAD_INSTANCE_TYPE"
echo "Web UI: https://${WEB_HOST}"
echo "Metrics: https://${WEB_HOST}:8001/metrics"
echo ""
echo "Verify GPU allocation:"
echo "  kubectl describe pod -n $NAMESPACE -l app=$WORKLOAD_NAME | grep -A5 nvidia.com/gpu"
echo ""
