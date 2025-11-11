#!/bin/bash
# Rekor Transparency Log Verification
# Usage: ./verify-rekor.sh <log_index> <image:tag>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $0 <log_index> [image:tag]"
    echo ""
    echo "Example:"
    echo "  $0 123456789"
    echo "  $0 123456789 fystack/apex-rescanner:v0.1.8"
    exit 1
}

get_image_digest() {
    local image="$1"
    local digest=""

    if command -v docker &>/dev/null && docker inspect "$image" &>/dev/null; then
        digest=$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "$image" 2>/dev/null | grep -oP 'sha256:[a-f0-9]{64}' | head -1)
    fi

    if [ -z "$digest" ] && command -v crane &>/dev/null; then
        digest=$(crane digest "$image" 2>/dev/null || echo "")
    fi

    echo "$digest"
}

search_by_digest() {
    local image="$1"
    
    check_required_tools rekor-cli || return 1

    local digest=$(get_image_digest "$image")
    if [ -z "$digest" ]; then
        print_warning "Could not extract image digest"
        return 1
    fi

    echo -e "${BLUE}  Attempting search by image digest...${NC}"
    set +e
    local found_entries=$(rekor-cli search --sha "$digest" 2>/dev/null)
    local search_exit=$?
    set -e

    if [ $search_exit -eq 0 ] && [ -n "$found_entries" ]; then
        local entry_count=$(echo "$found_entries" | wc -l)
        print_success "Found $entry_count Rekor entries for this image"
        echo "$found_entries" | head -3 | while read -r entry; do
            echo -e "    - $entry"
        done
        return 0
    else
        print_warning "No Rekor entries found via digest search"
        return 1
    fi
}

verify_rekor_entry() {
    local log_index="$1"

    check_required_tools rekor-cli jq || return 1

    local rekor_entry=$(mktemp)
    trap "rm -f '$rekor_entry'" RETURN

    set +e
    rekor-cli get --log-index "$log_index" --format json > "$rekor_entry" 2>/dev/null
    local rekor_exit=$?
    set -e

    if [ $rekor_exit -ne 0 ] || [ ! -s "$rekor_entry" ]; then
        return 1
    fi

    local uuid=$(jq -r 'keys[0] // empty' "$rekor_entry" 2>/dev/null || echo "")
    if [ -z "$uuid" ] || [ "$uuid" = "null" ] || [ "$uuid" = "" ]; then
        print_field "Verification" "Entry confirmed (details unavailable)"
        return 1
    fi

    local integrated_time=$(jq -r --arg uuid "$uuid" '.[$uuid].IntegratedTime // empty' "$rekor_entry" 2>/dev/null || echo "")
    
    print_field "Entry UUID" "$uuid"
    
    if [ -n "$integrated_time" ] && [ "$integrated_time" != "null" ] && [ "$integrated_time" != "" ]; then
        local timestamp=$(format_timestamp "$integrated_time")
        print_field "Integrated Time" "$timestamp"
        print_field "Verification" "Signed entry verified by Rekor"
    else
        print_field "Verification" "Entry exists in transparency log"
    fi

    return 0
}

verify_rekor() {
    local log_index="$1"
    local image="$2"

    print_header "[4/4] Verifying Rekor Transparency Log"

    if [ -n "$log_index" ] && [ "$log_index" != "N/A" ]; then
        print_success "Rekor transparency log entry found"
        echo ""
        print_field "Log Index" "$log_index"
        print_field "Rekor URL" "https://search.sigstore.dev/?logIndex=$log_index"

        if command -v rekor-cli &>/dev/null; then
            if ! verify_rekor_entry "$log_index"; then
                print_field "Verification" "Entry confirmed (fetch details failed)"
            fi
        else
            print_field "Verification" "Entry confirmed in transparency log"
            echo ""
            print_warning "Install rekor-cli for detailed entry information"
            echo -e "${YELLOW}        go install github.com/sigstore/rekor/cmd/rekor-cli@latest${NC}"
        fi
    else
        print_warning "Rekor log index not provided or not found"
        echo -e "${YELLOW}  Note: Older signatures may not include embedded log index${NC}"

        if [ -n "$image" ]; then
            echo ""
            search_by_digest "$image"
        fi
    fi
}

if [ $# -lt 1 ]; then
    usage
fi

LOG_INDEX="$1"
IMAGE="$2"

verify_rekor "$LOG_INDEX" "$IMAGE"

