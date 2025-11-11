#!/bin/bash
# SLSA Image Signature Verification
# Usage: ./verify-signature.sh <image:tag> [output_file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $0 <image:tag> [output_file]"
    echo ""
    echo "Example:"
    echo "  $0 fystack/apex-rescanner:v0.1.8"
    echo "  $0 fystack/apex-rescanner:v0.1.8 /tmp/signature.json"
    exit 1
}

verify_signature() {
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

    print_header "[1/4] Verifying Image Signature" >&2

    if ! cosign verify \
        --certificate-identity-regexp="$workflow" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$image" > "$output_file" 2>/dev/null; then
        print_error "Signature verification failed"
        echo -e "${RED}  The image signature could not be verified against the expected workflow${NC}" >&2
        [ "$temp_file" = true ] && rm -f "$output_file"
        return 1
    fi

    print_success "Signature verification passed" >&2
    echo "" >&2

    local cert_identity=$(jq -r '.[0].optional.Subject // "N/A"' "$output_file")
    local cert_issuer=$(jq -r '.[0].optional.Issuer // "N/A"' "$output_file")
    local bundle_time=$(jq -r '.[0].optional.Bundle.Payload.integratedTime // "N/A"' "$output_file")
    local log_index=$(jq -r '.[0].optional.Bundle.Payload.logIndex // "N/A"' "$output_file")
    local timestamp=$(format_timestamp "$bundle_time")

    print_field "Certificate Identity" "$cert_identity" >&2
    print_field "Certificate Issuer" "$cert_issuer" >&2
    print_field "Signed At" "$timestamp" >&2
    
    if [ "$log_index" != "N/A" ]; then
        print_field "Rekor Log Index" "$log_index" >&2
    fi
    echo "" >&2

    echo "$log_index"
}

if [ $# -lt 1 ]; then
    usage
fi

IMAGE="$1"
OUTPUT_FILE="$2"

verify_signature "$IMAGE" "$OUTPUT_FILE"

