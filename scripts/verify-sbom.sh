#!/bin/bash
# SBOM Attestation Verification
# Usage: ./verify-sbom.sh <image:tag> [output_file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $0 <image:tag> [output_file]"
    echo ""
    echo "Example:"
    echo "  $0 fystack/apex-rescanner:v0.1.8"
    echo "  $0 fystack/apex-rescanner:v0.1.8 /tmp/sbom.json"
    exit 1
}

verify_sbom() {
    local image="$1"
    local output_file="$2"
    local workflow="https://github.com/fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@.*"
    local temp_file=false

    if [ -z "$output_file" ]; then
        output_file=$(mktemp)
        temp_file=true
    fi

    local output_dir=$(dirname "$output_file")
    if [ ! -d "$output_dir" ]; then
        mkdir -p "$output_dir" || {
            print_error "Failed to create output directory: $output_dir"
            return 1
        }
    fi

    check_required_tools cosign jq || exit 1

    print_header "[3/4] Verifying SBOM Attestation"

    if ! cosign verify-attestation \
        --type spdx \
        --certificate-identity-regexp="$workflow" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$image" > "$output_file" 2>/dev/null; then
        print_warning "SBOM attestation not found or verification failed"
        echo -e "${YELLOW}  This may indicate SBOM generation is not enabled in the build workflow${NC}"
        echo -e "${YELLOW}  Set 'enable-sbom: true' in your workflow configuration${NC}"
        [ "$temp_file" = true ] && rm -f "$output_file"
        return 1
    fi

    print_success "SBOM attestation verification passed"
    echo ""

    local attestation=$(decode_payload "$output_file")
    
    # SBOM predicate is often double-encoded as a JSON string
    local sbom=$(echo "$attestation" | jq -r '.predicate')
    if echo "$sbom" | jq empty 2>/dev/null; then
        # predicate is already parsed JSON
        :
    else
        # predicate is a JSON string that needs parsing
        sbom=$(echo "$attestation" | jq -r '.predicate | fromjson')
    fi
    
    local sbom_version=$(echo "$sbom" | jq -r '.spdxVersion // "N/A"')
    local sbom_name=$(echo "$sbom" | jq -r '.name // "N/A"')
    local sbom_created=$(echo "$sbom" | jq -r '.creationInfo.created // "N/A"')
    local sbom_creators=$(echo "$sbom" | jq -r '.creationInfo.creators[]? // "N/A"' | paste -sd ',' -)

    print_field "SPDX Version" "$sbom_version"
    print_field "SBOM Name" "$sbom_name"
    print_field "Created" "$sbom_created"
    print_field "Creators" "$sbom_creators"
    echo ""

    local package_count=$(echo "$sbom" | jq -r '.packages | length // 0')
    local file_count=$(echo "$sbom" | jq -r '.files | length // 0')

    print_field "Total Packages" "$package_count"
    print_field "Total Files" "$file_count"
    
    local package_types=$(echo "$sbom" | jq -r '[.packages[].externalRefs[]?.referenceType // empty] | unique | join(", ")' 2>/dev/null)
    if [ -n "$package_types" ]; then
        print_field "Package Ecosystems" "$package_types"
    fi
    echo ""

    if [ "$package_count" != "0" ] && [ -n "$package_count" ] && [ "$package_count" -gt 0 ] 2>/dev/null; then
        echo -e "  ${BLUE}Sample Packages (top 5):${NC}"
        echo "$sbom" | jq -r '.packages[] | select(.name) | "    • \(.name) (\(.versionInfo // "unknown"))"' 2>/dev/null | head -5
        if [ "$package_count" -gt 5 ]; then
            echo -e "    ${BLUE}... and $((package_count - 5)) more${NC}"
        fi
    fi

    return 0
}

if [ $# -lt 1 ]; then
    usage
fi

IMAGE="$1"
OUTPUT_FILE="$2"

verify_sbom "$IMAGE" "$OUTPUT_FILE"

