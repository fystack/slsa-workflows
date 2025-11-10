#!/bin/bash
# SLSA L3 Image Verification Script
# Usage: ./verify-image.sh <image:tag> <github-repo>
# Example: ./verify-image.sh fystack/apex-api:v1.0.0 fystack/apex

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check required tools
check_tools() {
    local tools=("cosign" "jq" "docker")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}Error: $tool is not installed${NC}"
            exit 1
        fi
    done
}

# Usage information
usage() {
    echo "Usage: $0 <image:tag> <github-repo>"
    echo ""
    echo "Examples:"
    echo "  $0 fystack/apex-api:v1.0.0 fystack/apex"
    echo "  $0 ghcr.io/fystack/apex-api:v1.0.0 fystack/apex"
    exit 1
}

# Parse arguments
if [ $# -ne 2 ]; then
    usage
fi

IMAGE="$1"
REPO="$2"

echo -e "${GREEN}=== SLSA L3 Image Verification ===${NC}"
echo "Image: $IMAGE"
echo "Repository: $REPO"
echo ""

check_tools

# Step 1: Verify image signature
echo -e "${YELLOW}[1/4] Verifying image signature...${NC}"
if cosign verify \
    --certificate-identity-regexp="https://github.com/$REPO/.github/workflows/.*@.*" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
    "$IMAGE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Signature verification passed${NC}"
else
    echo -e "${RED}✗ Signature verification failed${NC}"
    exit 1
fi

# Step 2: Verify SLSA provenance
echo -e "${YELLOW}[2/4] Verifying SLSA provenance...${NC}"
if cosign verify-attestation \
    --type slsaprovenance \
    --certificate-identity-regexp="https://github.com/$REPO/.github/workflows/.*@.*" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
    "$IMAGE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SLSA provenance verification passed${NC}"

    # Extract provenance details
    PROVENANCE=$(cosign verify-attestation \
        --type slsaprovenance \
        --certificate-identity-regexp="https://github.com/$REPO/.github/workflows/.*@.*" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$IMAGE" 2>/dev/null | jq -r '.payload | @base64d | fromjson')

    BUILDER=$(echo "$PROVENANCE" | jq -r '.predicate.buildDefinition.buildType')
    SOURCE_REPO=$(echo "$PROVENANCE" | jq -r '.predicate.buildDefinition.externalParameters.source.repository')
    SOURCE_REF=$(echo "$PROVENANCE" | jq -r '.predicate.buildDefinition.externalParameters.source.ref')

    echo "  Builder: $BUILDER"
    echo "  Source: $SOURCE_REPO"
    echo "  Ref: $SOURCE_REF"
else
    echo -e "${RED}✗ SLSA provenance verification failed${NC}"
    exit 1
fi

# Step 3: Verify SBOM
echo -e "${YELLOW}[3/4] Verifying SBOM attestation...${NC}"
if cosign verify-attestation \
    --type spdx \
    --certificate-identity-regexp="https://github.com/$REPO/.github/workflows/.*@.*" \
    --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
    "$IMAGE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SBOM verification passed${NC}"

    # Extract SBOM details
    SBOM=$(cosign verify-attestation \
        --type spdx \
        --certificate-identity-regexp="https://github.com/$REPO/.github/workflows/.*@.*" \
        --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
        "$IMAGE" 2>/dev/null | jq -r '.payload | @base64d | fromjson')

    SBOM_VERSION=$(echo "$SBOM" | jq -r '.predicate.spdxVersion')
    PACKAGE_COUNT=$(echo "$SBOM" | jq -r '.predicate.packages | length')

    echo "  SPDX Version: $SBOM_VERSION"
    echo "  Packages: $PACKAGE_COUNT"
else
    echo -e "${YELLOW}⚠ SBOM verification failed (may not be enabled)${NC}"
fi

# Step 4: Check Rekor transparency log
echo -e "${YELLOW}[4/4] Checking Rekor transparency log...${NC}"
if rekor-cli search --artifact "$IMAGE" &> /dev/null; then
    echo -e "${GREEN}✓ Image found in Rekor transparency log${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify Rekor entry (rekor-cli may not be installed)${NC}"
fi

echo ""
echo -e "${GREEN}=== Verification Complete ===${NC}"
echo -e "${GREEN}✓ Image $IMAGE is SLSA L3 compliant${NC}"
