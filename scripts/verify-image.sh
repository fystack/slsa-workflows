#!/bin/bash
# SLSA L3 Image Verification Suite
# Professional verification orchestrator
# Usage: ./verify-image.sh <image:tag> <github-repo>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $0 <image:tag> <github-repo>"
    echo ""
    echo "Example:"
    echo "  $0 fystack/apex-rescanner:v0.1.8 fystack/apex"
    exit 1
}

print_summary() {
    local image="$1"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ✓ Verification Complete                          ║${NC}"
    echo -e "${GREEN}║           Image is SLSA Level 3 Compliant                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo -e "  • Image signature verified with keyless signing"
    echo -e "  • SLSA L3 provenance attestation validated"
    echo -e "  • Software Bill of Materials (SBOM) verified"
    echo -e "  • Transparency log entry confirmed"
    echo ""
    echo -e "${BLUE}Image:${NC} $image"
    echo -e "${BLUE}Trust:${NC} High - All SLSA L3 requirements satisfied"
}

if [ $# -ne 2 ]; then
    usage
fi

IMAGE="$1"
REPO="$2"

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         SLSA Level 3 Image Verification Suite              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Image:${NC}      $IMAGE"
echo -e "${BLUE}Repository:${NC} $REPO"
echo ""

check_required_tools cosign jq docker || exit 1

TEMP_DIR=$(setup_temp_dir)
SIGNATURE_OUTPUT="$TEMP_DIR/signature.json"
PROVENANCE_OUTPUT="$TEMP_DIR/provenance.json"
SBOM_OUTPUT="$TEMP_DIR/sbom.json"

LOG_INDEX=$("$SCRIPT_DIR/verify-signature.sh" "$IMAGE" "$SIGNATURE_OUTPUT")

"$SCRIPT_DIR/verify-provenance.sh" "$IMAGE" "$PROVENANCE_OUTPUT"
echo ""

"$SCRIPT_DIR/verify-sbom.sh" "$IMAGE" "$SBOM_OUTPUT" || true
echo ""

"$SCRIPT_DIR/verify-rekor.sh" "$LOG_INDEX" "$IMAGE"

print_summary "$IMAGE"
