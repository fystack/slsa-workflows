#!/bin/bash
# SLSA Provenance Verification
# Usage: ./verify-provenance.sh <image:tag> [output_file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $0 <image:tag> [output_file]"
    echo ""
    echo "Example:"
    echo "  $0 fystack/apex-rescanner:v0.1.8"
    echo "  $0 fystack/apex-rescanner:v0.1.8 /tmp/provenance.json"
    exit 1
}

extract_build_info() {
    local provenance="$1"
    local slsa_version="$2"

    if [[ "$slsa_version" == "v0.2" ]]; then
        echo "$provenance" | jq -r '.predicate.invocation.environment.github_event_name // "N/A"'
        echo "$provenance" | jq -r '.predicate.invocation.environment.github_ref // "N/A"'
        echo "$provenance" | jq -r '.predicate.invocation.environment.github_sha1 // "N/A"'
    else
        echo "$provenance" | jq -r '.predicate.buildConfig.eventName // "N/A"'
        echo "$provenance" | jq -r '.predicate.buildConfig.ref // "N/A"'
        echo "$provenance" | jq -r '.predicate.buildConfig.sha // "N/A"'
    fi
}

verify_provenance() {
    local image="$1"
    local output_file="$2"
    local workflow="https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@.*"
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

    print_header "[2/4] Verifying SLSA Provenance"

    if ! cosign verify-attestation \
        --type slsaprovenance \
        --certificate-identity-regexp="$workflow" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$image" > "$output_file" 2>/dev/null; then
        print_error "SLSA provenance verification failed"
        echo -e "${RED}  The SLSA provenance attestation could not be verified${NC}" >&2
        [ "$temp_file" = true ] && rm -f "$output_file"
        return 1
    fi

    print_success "SLSA provenance verification passed"
    echo ""

    local provenance=$(decode_payload "$output_file")
    
    local builder_id=$(echo "$provenance" | jq -r '.predicate.builder.id // "N/A"')
    local build_type=$(echo "$provenance" | jq -r '.predicate.buildType // "N/A"')
    local predicate_type=$(echo "$provenance" | jq -r '.predicateType // "N/A"')
    local slsa_version=$(echo "$predicate_type" | grep -oP 'v[0-9.]+' || echo "N/A")

    print_field "SLSA Version" "$slsa_version"
    print_field "Builder" "$builder_id"
    print_field "Build Type" "$build_type"
    echo ""

    local source_uri=$(echo "$provenance" | jq -r '.predicate.invocation.configSource.uri // "N/A"')
    local source_digest=$(echo "$provenance" | jq -r '.predicate.invocation.configSource.digest.sha1 // "N/A"')
    local source_entry=$(echo "$provenance" | jq -r '.predicate.invocation.configSource.entryPoint // "N/A"')

    print_field "Source Repository" "$source_uri"
    print_field "Source Digest" "$source_digest"
    print_field "Entry Point" "$source_entry"
    echo ""

    local build_info=($(extract_build_info "$provenance" "$slsa_version"))
    local build_trigger="${build_info[0]}"
    local build_ref="${build_info[1]}"
    local build_sha="${build_info[2]}"

    print_field "Build Trigger" "$build_trigger"
    print_field "Build Ref" "$build_ref"
    if [ "$build_sha" != "N/A" ]; then
        print_field "Build SHA" "${build_sha:0:12}..."
    else
        print_field "Build SHA" "N/A"
    fi
    echo ""

    local material_count=$(echo "$provenance" | jq -r '.predicate.materials | length // 0')
    if [ "$material_count" -gt 0 ]; then
        print_field "Build Materials" "$material_count dependencies"
        echo "$provenance" | jq -r '.predicate.materials[] | "    - \(.uri // .name)"' | head -5
        if [ "$material_count" -gt 5 ]; then
            echo "    ... and $((material_count - 5)) more"
        fi
    fi
}

if [ $# -lt 1 ]; then
    usage
fi

IMAGE="$1"
OUTPUT_FILE="$2"

verify_provenance "$IMAGE" "$OUTPUT_FILE"

