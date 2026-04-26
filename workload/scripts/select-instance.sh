#!/bin/bash
# -----------------------------------------------------------------------------
# Description: Interactive Linode instance selector for Karpenter nodepools
# Usage: LINODE_CLI_NS=kube-system LINODE_REGION=de-fra-2 ./select-instance.sh [instance-type-id]
#   - Without args: interactive selection menu grouped by class/GPU label
#   - With instance-type-id: validates and returns if available, else suggests alternatives
#   - LINODE_REGION: override auto-detection
#   - LINODE_CLI_NS: namespace where linode-cli pod runs (default: kube-system)
# Output: Prints selected instance type ID to stdout
# Exit: 0 success, 1 error/cancelled
# Requires: jq
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." &>/dev/null && pwd)"

ENV_LOCATIONS="$SCRIPT_DIR/../../.env $SCRIPT_DIR/../.env"

for env_file in $ENV_LOCATIONS; do
    if [ -f "$env_file" ]; then
        set -a
        source "$env_file"
        set +a
        break
    fi
done

NAMESPACE="${LINODE_CLI_NS:-kube-system}"

check_dependency() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed" >&2
        exit 1
    fi
}

fetch_types() {
    kubectl exec -it linode-cli -n "$NAMESPACE" -- \
        linode-cli linodes types --json 2>/dev/null
}

fetch_availability() {
    local region="$1"
    kubectl exec -it linode-cli -n "$NAMESPACE" -- /bin/sh -c \
        "python3 -c \"import urllib.request, json; print(urllib.request.urlopen('https://api.linode.com/v4beta/regions/$region/availability').read().decode())\"" 2>/dev/null | jq 'map({plan: .plan, available: .available})'
}

detect_region() {
    local node_ip
    node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")

    if [ -n "$node_ip" ]; then
        local region
        region=$(kubectl exec -it linode-cli -n "$NAMESPACE" -- \
            linode-cli linodes types --json 2>/dev/null | jq -r '[.[] | select(.region_prices | length > 0)][0].region_prices[0].id' 2>/dev/null || echo "")
        if [ -n "$region" ] && [ "$region" != "null" ]; then
            echo "$region"
        else
            echo "de-fra-2"
        fi
    else
        echo "de-fra-2"
    fi
}

extract_gpu_label() {
    local label="$1"
    label=$(echo "$label" | tr '\n' ' ' | sed 's/  */ /g')

    if echo "$label" | grep -qi "RTX4000.*Ada\|Ada.*RTX4000"; then
        echo "RTX4000 Ada"
    elif echo "$label" | grep -qi "RTX6000"; then
        echo "RTX6000"
    elif echo "$label" | grep -qi "RTX5000"; then
        echo "RTX5000"
    elif echo "$label" | grep -qi "A100"; then
        echo "A100"
    elif echo "$label" | grep -qi "H100"; then
        echo "H100"
    else
        echo "Other"
    fi
}

add_gpu_labels() {
    local types_json="$1"

    echo "$types_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r instance; do
        local id class label vcpus memory disk gpus price region_prices
        id=$(echo "$instance" | jq -r '.id')
        class=$(echo "$instance" | jq -r '.class')
        label=$(echo "$instance" | jq -r '.label')
        vcpus=$(echo "$instance" | jq -r '.vcpus')
        memory=$(echo "$instance" | jq -r '.memory')
        disk=$(echo "$instance" | jq -r '.disk')
        gpus=$(echo "$instance" | jq -r '.gpus')
        price=$(echo "$instance" | jq -r '.price.hourly')
        region_prices=$(echo "$instance" | jq -c '.region_prices')

        local gpu_label
        gpu_label=$(extract_gpu_label "$label")

        echo "$instance" | jq --arg gpu_label "$gpu_label" --argjson region_prices "$region_prices" -c '{
            id: .id,
            class: .class,
            vcpus: .vcpus,
            memory: .memory,
            disk: .disk,
            gpus: .gpus,
            label: (.label | gsub("\n"; " ") | gsub("  +"; " ")),
            price: .price.hourly,
            gpu_label: $gpu_label,
            region_prices: $region_prices
        }'
    done | jq -s 'sort_by(.class, .vcpus, .memory)'
}

filter_by_region() {
    local instances_json="$1"
    local target_region="${2:-eu-central}"

    local availability_json
    availability_json=$(fetch_availability "$target_region")

    if [ -z "$availability_json" ] || [ "$availability_json" = "[]" ]; then
        echo "$instances_json"
        return
    fi

    echo "$instances_json" | jq -c --argjson avail "$availability_json" '
        def available_plans: $avail | map(select(.available) | .plan);
        [
            .[] | select(.id as $id | available_plans | index($id) != null)
        ]
    '
}

validate_instance() {
    local instance_id="$1"
    local instances_json="$2"

    local found
    found=$(echo "$instances_json" | jq -r --arg id "$instance_id" '.[] | select(.id == $id) | .id' 2>/dev/null)

    [ -n "$found" ] && [ "$found" != "null" ]
}

find_alternatives() {
    local requested_id="$1"
    local instances_json="$2"

    local class
    class=$(echo "$instances_json" | jq -r --arg id "$requested_id" '.[] | select(.id == $id) | .class' 2>/dev/null)

    if [ -z "$class" ] || [ "$class" = "null" ]; then
        return 1
    fi

    local gpu_label
    gpu_label=$(echo "$instances_json" | jq -r --arg id "$requested_id" '.[] | select(.id == $id) | .gpu_label' 2>/dev/null)

    echo "$instances_json" | jq -c --arg class "$class" --arg gpu_label "$gpu_label" \
        '[.[] | select(.class == $class and .gpu_label == $gpu_label and .id != $class)]' 2>/dev/null
}

show_alternatives() {
    local alternatives_json="$1"

    local count
    count=$(echo "$alternatives_json" | jq 'length' 2>/dev/null || echo 0)

    if [ "$count" -eq 0 ]; then
        echo "No alternative instances found." >&2
        return 1
    fi

    echo ""
    echo "Available alternatives:"
    echo ""

    local i=1
    while IFS= read -r instance; do
        [ -z "$instance" ] && continue
        local id vcpus memory price
        id=$(echo "$instance" | jq -r '.id')
        vcpus=$(echo "$instance" | jq -r '.vcpus')
        memory=$(echo "$instance" | jq -r '.memory')
        price=$(echo "$instance" | jq -r '.price')
        echo "  [$i] $id | ${vcpus}v | ${memory}MB | \$${price}/hr"
        i=$((i + 1))
    done <<< "$(echo "$alternatives_json" | jq -c '.[]' 2>/dev/null)"

    echo ""
    echo "Enter selection [1-$((i - 1))] or 'q' to quit: "
    read -r sel

    if [ "$sel" = "q" ] || [ "$sel" = "Q" ]; then
        echo "Cancelled." >&2
        exit 1
    fi

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$((i - 1))" ]; then
        echo "Invalid selection." >&2
        exit 1
    fi

    echo "$alternatives_json" | jq -r ".[$((sel - 1))].id"
}

select_from_menu() {
    local instances_json="$1"

    local total
    total=$(echo "$instances_json" | jq 'length')

    if [ "$total" -eq 0 ]; then
        echo "Error: No instances found" >&2
        exit 1
    fi

    local current_class=""
    local idx=1

    while IFS= read -r instance; do
        [ -z "$instance" ] && continue

        local id class gpu_label vcpus memory price
        id=$(echo "$instance" | jq -r '.id')
        class=$(echo "$instance" | jq -r '.class')
        gpu_label=$(echo "$instance" | jq -r '.gpu_label')
        vcpus=$(echo "$instance" | jq -r '.vcpus')
        memory=$(echo "$instance" | jq -r '.memory')
        price=$(echo "$instance" | jq -r '.price')

        if [ "$class" != "$current_class" ]; then
            echo ""
            echo "=== $class ($gpu_label) ==="
            echo ""
            current_class="$class"
        fi

        echo "  [$idx] $id | ${vcpus}v | ${memory}MB | \$${price}/hr"
        idx=$((idx + 1))
    done <<< "$(echo "$instances_json" | jq -c '.[]' 2>/dev/null)"

    echo ""
    echo "Enter selection [1-$total], 'q' to quit: "
    read -r sel

    if [ "$sel" = "q" ] || [ "$sel" = "Q" ]; then
        echo "Cancelled."
        exit 0
    fi

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$total" ]; then
        echo "Invalid selection '$sel'. Must be between 1 and $total." >&2
        exit 1
    fi

    local selected_id
    selected_id=$(echo "$instances_json" | jq -r ".[$((sel - 1))].id")

    if [ -z "$selected_id" ] || [ "$selected_id" = "null" ]; then
        echo "Error: Could not find selected instance" >&2
        exit 1
    fi

    echo "$selected_id"
}

main() {
    check_dependency

    local target_region="${LINODE_REGION:-}"
    if [ -z "$target_region" ]; then
        echo "==> Detecting cluster region..."
        target_region=$(detect_region)
    fi
    echo "==> Filtering instances for region: $target_region"

    echo "==> Fetching Linode instance types..."
    local types_json
    types_json=$(fetch_types)

    if [ -z "$types_json" ] || [ "$types_json" = "null" ]; then
        echo "Error: Failed to fetch instance types" >&2
        exit 1
    fi

    echo "==> Processing instance data..."
    local instances_json
    instances_json=$(add_gpu_labels "$types_json")

    if [ -z "$instances_json" ] || [ "$instances_json" = "[]" ]; then
        echo "Error: Failed to process instance types" >&2
        exit 1
    fi

    local filtered_json
    filtered_json=$(filter_by_region "$instances_json" "$target_region")

    if [ -z "$filtered_json" ] || [ "$filtered_json" = "[]" ]; then
        echo "Error: No instances available in region $target_region" >&2
        exit 1
    fi

    echo "==> Found $(echo "$filtered_json" | jq 'length') available instance types in $target_region"

    if [ $# -gt 0 ]; then
        local requested_id="$1"

        if validate_instance "$requested_id" "$filtered_json"; then
            echo "$requested_id"
            exit 0
        else
            echo "Instance '$requested_id' not available in region $target_region." >&2

            local alternatives_json
            alternatives_json=$(find_alternatives "$requested_id" "$filtered_json")

            if [ -n "$alternatives_json" ] && [ "$alternatives_json" != "[]" ] && [ "$alternatives_json" != "null" ]; then
                local selected
                selected=$(show_alternatives "$alternatives_json")
                echo "$selected"
                exit 0
            fi

            echo "No alternatives found in same class/GPU group." >&2
            exit 1
        fi
    fi

    select_from_menu "$filtered_json"
}

main "$@"
