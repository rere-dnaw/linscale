#!/bin/bash
# -----------------------------------------------------------------------------
# k8scale - Kubernetes cluster setup orchestration
# Main entry point for deploying/destroying cluster components
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

STAGES=("linode-cli" "linode-firewall" "cert-manager" "traefik" "karpenter")
DEPLOY_ORDER=("linode-cli" "linode-firewall" "cert-manager" "traefik")
DESTROY_ORDER=("traefik" "cert-manager" "linode-firewall" "linode-cli")

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [stage]

Commands:
    deploy <stage|all>   Deploy stage(s)
    destroy <stage|all>   Destroy stage(s) in reverse order
    status               Show deployed components
    help                 Show this help

Stages:
    linode-cli           Linode CLI pod with credentials
    linode-firewall      Linode Cloud Firewall controller
    cert-manager         cert-manager with Linode DNS-01 solver
    traefik              Traefik ingress controller
    karpenter            Karpenter GPU nodes (NOT IMPLEMENTED - placeholder)

Examples:
    $(basename "$0") deploy all          # Deploy everything
    $(basename "$0") destroy all         # Destroy everything
    $(basename "$0") deploy cert-manager # Deploy only cert-manager
    $(basename "$0") destroy traefik     # Destroy only traefik
    $(basename "$0") status             # Show status

EOF
}

validate_stage() {
    local stage="$1"
    for s in "${STAGES[@]}"; do
        if [ "$s" = "$stage" ]; then
            return 0
        fi
    done
    return 1
}

deploy_stage() {
    local stage="$1"
    local stage_dir="$SCRIPT_DIR/$stage"

    if [ "$stage" = "karpenter" ]; then
        echo ""
        echo "========================================"
        echo "KARPENTER STAGE IS NOT IMPLEMENTED YET"
        echo "========================================"
        echo ""
        echo "This is a placeholder. Karpenter GPU node provisioning"
        echo "is planned for future implementation."
        echo ""
        echo "Current implemented stages:"
        printf '  - %s\n' "${DEPLOY_ORDER[@]}"
        echo ""
        return 0
    fi

    if [ ! -d "$stage_dir" ]; then
        echo "Error: Stage directory '$stage_dir' not found"
        return 1
    fi

    if [ ! -f "$stage_dir/deploy.sh" ]; then
        echo "Error: deploy.sh not found for stage '$stage'"
        return 1
    fi

    echo ""
    echo "==> Deploying $stage..."
    echo "========================================"

    if [ "$stage" = "linode-cli" ]; then
        LINODE_TOKEN="$LINODE_CLI_TOKEN" LINODE_CLI_NS="${LINODE_CLI_NS:-default}" bash "$stage_dir/deploy.sh"
    elif [ "$stage" = "cert-manager" ]; then
        CERT_MANAGER_TOKEN="$CERT_MANAGER_TOKEN" CERT_MANAGER_EMAIL="$CERT_MANAGER_EMAIL" CERT_MANAGER_NS="${CERT_MANAGER_NS:-cert-manager}" bash "$stage_dir/deploy.sh"
    elif [ "$stage" = "traefik" ]; then
        TRAEFIK_NS="${TRAEFIK_NS:-traefik}" TRAEFIK_DOMAIN="${TRAEFIK_DOMAIN}" TRAEFIK_USER="${TRAEFIK_USER}" TRAEFIK_PASSWORD="${TRAEFIK_PASSWORD}" bash "$stage_dir/deploy.sh"
    elif [ "$stage" = "linode-firewall" ]; then
        LINODE_FIREWALL_NS="${LINODE_FIREWALL_NS:-kube-system}" bash "$stage_dir/deploy.sh"
    else
        bash "$stage_dir/deploy.sh"
    fi

    echo "==> $stage deployed successfully"
}

destroy_stage() {
    local stage="$1"
    local stage_dir="$SCRIPT_DIR/$stage"

    if [ "$stage" = "karpenter" ]; then
        echo ""
        echo "========================================"
        echo "KARPENTER STAGE IS NOT IMPLEMENTED YET"
        echo "========================================"
        echo ""
        return 0
    fi

    if [ ! -d "$stage_dir" ]; then
        echo "Error: Stage directory '$stage_dir' not found"
        return 1
    fi

    if [ ! -f "$stage_dir/destroy.sh" ]; then
        echo "Error: destroy.sh not found for stage '$stage'"
        return 1
    fi

    echo ""
    echo "==> Destroying $stage..."
    echo "========================================"

    if [ "$stage" = "linode-cli" ]; then
        LINODE_CLI_NS="${LINODE_CLI_NS:-default}" bash "$stage_dir/destroy.sh"
    elif [ "$stage" = "cert-manager" ]; then
        CERT_MANAGER_NS="${CERT_MANAGER_NS:-cert-manager}" bash "$stage_dir/destroy.sh"
    elif [ "$stage" = "traefik" ]; then
        TRAEFIK_NS="${TRAEFIK_NS:-traefik}" bash "$stage_dir/destroy.sh"
    elif [ "$stage" = "linode-firewall" ]; then
        LINODE_FIREWALL_NS="${LINODE_FIREWALL_NS:-kube-system}" bash "$stage_dir/destroy.sh"
    else
        bash "$stage_dir/destroy.sh"
    fi

    echo "==> $stage destroyed"
}

show_status() {
    local linode_cli_ns="${LINODE_CLI_NS:-default}"
    local cert_manager_ns="${CERT_MANAGER_NS:-cert-manager}"
    local traefik_ns="${TRAEFIK_NS:-traefik}"

    echo ""
    echo "=== k8scale Status ==="
    echo ""

    echo "--- Namespaces ---"
    kubectl get namespaces 2>/dev/null | grep -E "default|cert-manager|traefik|skynet|kube-system" || echo "  (none found)"

    echo ""
    echo "--- linode-cli Pod ---"
    kubectl get pod linode-cli -n "$linode_cli_ns" 2>/dev/null || echo "  Not deployed"

    echo ""
    echo "--- cert-manager ---"
    kubectl get pods -n "$cert_manager_ns" 2>/dev/null | head -5 || echo "  Not deployed"

    echo ""
    echo "--- Traefik ---"
    kubectl get pods -n "$traefik_ns" 2>/dev/null | head -5 || echo "  Not deployed"

    echo ""
    echo "--- ClusterIssuers ---"
    kubectl get clusterissuer 2>/dev/null || echo "  None found"

    echo ""
    echo "--- Certificates ---"
    kubectl get certificates --all-namespaces 2>/dev/null | head -10 || echo "  None found"

    echo ""
}

CMD="${1:-help}"
STAGE="${2:-}"

case "$CMD" in
    deploy)
        if [ -z "$STAGE" ]; then
            echo "Error: stage required (use 'all' or a specific stage)"
            echo "Available stages: ${STAGES[*]}"
            exit 1
        fi

        if [ "$STAGE" = "all" ]; then
            for s in "${DEPLOY_ORDER[@]}"; do
                deploy_stage "$s" || { echo "Failed at $s"; exit 1; }
            done
            echo ""
            echo "========================================"
            echo "All stages deployed successfully!"
            echo "========================================"
        else
            if validate_stage "$STAGE"; then
                deploy_stage "$STAGE"
            else
                echo "Error: unknown stage '$STAGE'"
                echo "Available stages: ${STAGES[*]}"
                exit 1
            fi
        fi
        ;;

    destroy)
        if [ -z "$STAGE" ]; then
            echo "Error: stage required (use 'all' or a specific stage)"
            echo "Available stages: ${STAGES[*]}"
            exit 1
        fi

        if [ "$STAGE" = "all" ]; then
            for s in "${DESTROY_ORDER[@]}"; do
                destroy_stage "$s" || { echo "Failed at $s"; exit 1; }
            done
            echo ""
            echo "========================================"
            echo "All stages destroyed successfully!"
            echo "========================================"
        else
            if validate_stage "$STAGE"; then
                destroy_stage "$STAGE"
            else
                echo "Error: unknown stage '$STAGE'"
                echo "Available stages: ${STAGES[*]}"
                exit 1
            fi
        fi
        ;;

    status)
        show_status
        ;;

    help|--help|-h)
        usage
        ;;

    *)
        usage
        exit 1
        ;;
esac