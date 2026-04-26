#!/bin/bash
# -----------------------------------------------------------------------------
# Deploys workload with Karpenter nodepool, TLS, PVC, firewall
# Usage: ./deploy.sh [--last-run]
# -----------------------------------------------------------------------------
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOAD_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$WORKLOAD_DIR")"

# Load infra config
if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

# Load workload config
if [ -f "$WORKLOAD_DIR/.env" ]; then
    set -a
    source "$WORKLOAD_DIR/.env"
    set +a
fi

# Handle --last-run
if [ "${1:-}" = "--last-run" ]; then
    LAST_RUN_FILE="$WORKLOAD_DIR/${WORKLOAD_NAME}.last-run.yaml"
    if [ -f "$LAST_RUN_FILE" ]; then
        echo "==> Loading last run config from $LAST_RUN_FILE"
        WORKLOAD_NAME=$(grep -E '^WORKLOAD_NAME:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        WORKLOAD_IMAGE=$(grep -E '^WORKLOAD_IMAGE:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        WORKLOAD_INSTANCE_TYPE=$(grep -E '^WORKLOAD_INSTANCE_TYPE:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        PVC_ENABLED=$(grep -E '^PVC_ENABLED:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
        EXTRA_PORTS=$(grep -E '^EXTRA_PORTS:' "$LAST_RUN_FILE" | cut -d: -f2 | tr -d ' ')
    else
        echo "Warning: Last run file not found, using .env config"
    fi
fi

NAMESPACE="${WORKLOAD_NS:-workloads}"
WORKLOAD_NAME="${WORKLOAD_NAME:?WORKLOAD_NAME required}"
IMAGE="${WORKLOAD_IMAGE:-nginx:latest}"
WEB_PORT="${WEB_PORT:-8080}"
ENABLE_TLS="${ENABLE_TLS:-true}"
PVC_ENABLED="${PVC_ENABLED:-true}"

# 1. Validate prerequisites
echo "==> Validating prerequisites..."
kubectl cluster-info 2>/dev/null || { echo "Error: No cluster connection"; exit 1; }
kubectl get pod linode-cli -n "${LINODE_CLI_NS:-default}" 2>/dev/null || { echo "Error: linode-cli not running"; exit 1; }
kubectl get pods -n "${LINODE_FIREWALL_NS:-kube-system}" -l app.kubernetes.io/name=cloud-firewall-controller 2>/dev/null | grep -q Running || { echo "Error: cloud-firewall-controller not ready"; exit 1; }

# 2. Select instance type if not set
if [ -z "$WORKLOAD_INSTANCE_TYPE" ]; then
    echo "==> Selecting instance type..."
    export LINODE_CLI_NS="${LINODE_CLI_NS:-default}"
    WORKLOAD_INSTANCE_TYPE=$("$SCRIPT_DIR/select-instance.sh")
    echo "==> Selected: $WORKLOAD_INSTANCE_TYPE"
fi

# 3. Create namespace
echo "==> Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 4. Generate extra ports YAML blocks in bash
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
      action: \"ACCEPT\"
      description: \"${name} access for ${WORKLOAD_NAME}\"
      protocol: \"${protocol}\"
      ports: \"${port}\"
      addresses:
        ipv4:
          - \"0.0.0.0/0\""
    done
fi
export EXTRA_PORTS_SVC EXTRA_PORTS_FW

# 5. Save last run config
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

# 6. Apply nodepool
echo "==> Creating Karpenter nodepool..."
CPU_LIMIT_NUMERIC=$(echo "${CPU_LIMIT:-2000m}" | grep -oE '[0-9]+')
export CPU_LIMIT_NUMERIC
envsubst < "$SCRIPT_DIR/templates/nodepool.yaml.tpl" | kubectl apply -f -

# 7. Apply deployment
echo "==> Deploying workload..."
envsubst < "$SCRIPT_DIR/templates/deployment.yaml.tpl" | kubectl apply -f -

# 8. Apply service
echo "==> Creating service..."
envsubst < "$SCRIPT_DIR/templates/service.yaml.tpl" | kubectl apply -f -

# 9. Apply IngressRoute + Certificate (TLS)
if [ "$ENABLE_TLS" = "true" ]; then
    echo "==> Configuring TLS..."
    envsubst < "$SCRIPT_DIR/templates/ingress.yaml.tpl" | kubectl apply -f -
    envsubst < "$SCRIPT_DIR/templates/cert.yaml.tpl" | kubectl apply -f -
fi

# 10. Apply PVC
if [ "$PVC_ENABLED" = "true" ]; then
    echo "==> Creating PVC..."
    envsubst < "$SCRIPT_DIR/templates/pvc.yaml.tpl" | kubectl apply -f -

    echo "==> Mounting PVC in deployment..."
    kubectl patch deployment "$WORKLOAD_NAME" -n "$NAMESPACE" \
        --type json \
        -p "[{\"op\": \"add\", \"path\": \"/spec/template/spec/volumes\", \"value\":[{\"name\": \"data\", \"persistentVolumeClaim\": {\"claimName\": \"${WORKLOAD_NAME}-data\"}}]}]"
    kubectl patch deployment "$WORKLOAD_NAME" -n "$NAMESPACE" \
        --type json \
        -p "[{\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/volumeMounts\", \"value\":[{\"name\": \"data\", \"mountPath\": \"/data\"}]}]"
fi

# 11. Apply firewall
echo "==> Creating firewall rules..."
envsubst < "$SCRIPT_DIR/templates/firewall.yaml.tpl" | kubectl apply -f -

# 12. Wait for deployment
echo "==> Waiting for deployment..."
kubectl wait --for=condition=available deployment/${WORKLOAD_NAME} -n "$NAMESPACE" --timeout=300s

echo ""
echo "========================================"
echo "Deployment complete!"
echo "========================================"
echo "Workload: $WORKLOAD_NAME"
echo "Namespace: $NAMESPACE"
echo "Instance: $WORKLOAD_INSTANCE_TYPE"
echo "Web UI: https://${WEB_HOST}"
if [ -n "$EXTRA_PORTS" ]; then
    echo "Extra ports: $EXTRA_PORTS (NodePort)"
fi
echo ""