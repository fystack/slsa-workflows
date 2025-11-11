#!/bin/bash
# Common utilities for SLSA verification scripts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

setup_temp_dir() {
    local temp_dir=$(mktemp -d)
    if [ ! -d "$temp_dir" ]; then
        echo -e "${RED}Error: Failed to create temporary directory${NC}" >&2
        return 1
    fi
    trap "rm -rf '$temp_dir'" EXIT
    echo "$temp_dir"
}

check_required_tools() {
    local missing=0
    for tool in "$@"; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${RED}Error: $tool is not installed${NC}" >&2
            case "$tool" in
                cosign) echo "  Install: brew install cosign or visit https://docs.sigstore.dev/cosign/installation/" >&2 ;;
                jq) echo "  Install: brew install jq or apt-get install jq" >&2 ;;
                docker) echo "  Install: https://docs.docker.com/get-docker/" >&2 ;;
                rekor-cli) echo "  Install: go install github.com/sigstore/rekor/cmd/rekor-cli@latest" >&2 ;;
            esac
            missing=1
        fi
    done
    return $missing
}

print_header() {
    local title="$1"
    echo -e "${YELLOW}$title${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_field() {
    local label="$1"
    local value="$2"
    printf "  ${BLUE}%-20s${NC} %s\n" "$label:" "$value"
}

decode_payload() {
    local file="$1"
    jq -r '.payload | @base64d | fromjson' "$file"
}

format_timestamp() {
    local timestamp="$1"
    if [ "$timestamp" != "N/A" ] && [ -n "$timestamp" ]; then
        date -d "@$timestamp" -u +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || echo "$timestamp"
    else
        echo "N/A"
    fi
}

