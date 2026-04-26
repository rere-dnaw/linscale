#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${LINODE_FIREWALL_NS:-kube-system}"

case "${1:-}" in
    workload-apply)
        WORKLOAD_NAME="${2:?}"
        WORKLOAD_NS="${3:-workloads}"
        EXTRA_PORTS_FW="${4:-}"
        TEMPLATE="${SCRIPT_DIR}/../workload/templates/firewall.yaml.tpl"

        if [ ! -f "$TEMPLATE" ]; then
            echo "Error: Firewall template not found at $TEMPLATE"
            exit 1
        fi

        echo "==> Applying firewall rules for $WORKLOAD_NAME..."
        export WORKLOAD_NAME WORKLOAD_NS EXTRA_PORTS_FW
        envsubst < "$TEMPLATE" | kubectl apply -f -
        echo "==> Firewall rules applied for $WORKLOAD_NAME"
        ;;

    workload-remove)
        WORKLOAD_NAME="${2:?}"
        echo "==> Removing firewall rules for $WORKLOAD_NAME..."
        kubectl delete CloudFirewall "$WORKLOAD_NAME" 2>/dev/null || true
        echo "==> Firewall rules removed for $WORKLOAD_NAME"
        ;;

    *)
        echo "==> Installing CloudFirewall CRD and controller..."
        helm repo add linode-cfw https://linode.github.io/cloud-firewall-controller 2>/dev/null || true
        helm repo update

        helm upgrade --install cloud-firewall-crd linode-cfw/cloud-firewall-crd \
          --namespace "$NAMESPACE"

        kubectl wait --for condition=established --timeout=60s crd/cloudfirewalls.networking.linode.com

        helm upgrade --install cloud-firewall linode-cfw/cloud-firewall-controller \
          --namespace "$NAMESPACE" \
          --values "${SCRIPT_DIR}/values.yaml"
        echo "==> CloudFirewall CRD and controller installed"
        ;;
esac
