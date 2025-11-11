# Fystack's Image SLSA Level 3 Workflows

## Key Features

  * **SLSA Level 3 Compliance**: Generates non-forgeable provenance using the official `slsa-framework/slsa-github-generator`.
  * **Keyless Signing**: Automatic image signing via **Cosign** using GitHub OIDC. No key management is required.
  * **Transparency**: Signatures are recorded in the **Rekor** public transparency log.
  * **SBOM Generation**: Optionally generates a Software Bill of Materials (SBOM) attestation.
  * **Multi-Registry Support**: Works with Docker Hub, GHCR, and GCR.
  * **Enterprise Ready**: Uses security best practices, including non-root users and reproducible builds.

## Workflow: `docker-build-slsa.yml`

This reusable workflow automates the secure build and publishing process:

1.  **Build**: Docker image build with BuildKit optimizations.
2.  **Push**: Push to the container registry with generated tags.
3.  **SBOM**: Generate SBOM (optional).
4.  **Provenance**: Generate SLSA L3 provenance in an isolated job.
5.  **Sign**: Keyless signing with Cosign.
6.  **Publish**: Attach attestations (provenance, SBOM) to the registry.

### Usage Example

A job utilizing the workflow:

```yaml
jobs:
  build:
    permissions:
      contents: read
      packages: write
      id-token: write # Required for keyless signing/provenance
      actions: read
    uses: fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@main
    with:
      image-name: myorg/myapp
      context-path: .
      dockerfile: Dockerfile
      registry: dockerhub
    secrets:
      registry-username: ${{ secrets.DOCKER_USERNAME }}
      registry-password: ${{ secrets.DOCKER_TOKEN }}
```

### Inputs and Secrets

| Input | Required | Description |
| :--- | :--- | :--- |
| `image-name` | **Yes** | Full Docker image name (e.g., `fystack/apex-api`). |
| `context-path` | **Yes** | Build context path relative to repository root. |
| `dockerfile` | **Yes** | Path to Dockerfile relative to context. |
| `platforms` | No | Target platforms (comma-separated, default: `linux/amd64`). |
| `enable-sbom` | No | Generate SBOM attestation (default: `true`). |
| `registry` | No | Container registry: `dockerhub`, `ghcr`, or `gcr` (default: `dockerhub`). |

| Secret | Required | Description |
| :--- | :--- | :--- |
| `registry-username` | **Yes** | Registry username (Docker Hub username, GitHub actor, etc.). |
| `registry-password` | **Yes** | Registry password or token. |


## Understanding SLSA Provenance and Security Layers

The primary function of SLSA provenance is to create an **unforgeable record** that details *how*, *when*, and *from what source code* an artifact (Docker image) was built. This provides the highest level of assurance against tampering and injection attacks.

This workflow enforces a **three-layer security model**:

| Layer | Verification Method | What It Proves | Attack Scenario Stopped |
| :--- | :--- | :--- | :--- |
| **1. Digest** | Pull by digest (`image@sha256:...`) | The specific image contents have not changed *after* the build. | Image tampering *after* push to registry. |
| **2. Signature** | `cosign verify` | The image was built by the trusted CI/CD workflow (signer). | Unauthorized builds or compromised registry pushing unsigned images. |
| **3. Provenance (Commit)** | Compare commit in provenance vs. git tag | The image was built from the **expected source code commit**. | Code injection *before* the build that would produce a signed image from unexpected source code. **This is the critical defense against supply chain attacks.** |


## Verifying SLSA Attestations

Verification is essential to complete the security chain.

### Manual Verification Steps

#### 1\. Verify Image Signature

Proves the image was signed by the official SLSA workflow.

```bash
cosign verify \
  --certificate-identity-regexp='https://github.com/fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0
```

#### 2\. Verify SLSA Provenance (The "How" and "What")

Proves the image was built from specific source code, not tampered with.

```bash
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp='https://github.com/fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0 \
  | jq '.payload | @base64d | fromjson'
```

#### 3\. Critical Security Check: Detect Code Injection

This step compares the commit SHA recorded in the image's provenance with the expected commit for the given Git tag. If they don't match, malicious code was injected before the build process.

```bash
# 1. Extract the commit SHA from the image's SLSA provenance
ACTUAL_COMMIT=$(cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp='https://github.com/fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0 2>/dev/null \
  | jq -r '.payload | @base64d | fromjson | .predicate.materials[0].digest.sha1')

# 2. Get the expected commit SHA for the tag from your source control
EXPECTED_COMMIT=$(git rev-parse v1.0.0)

# 3. Compare
if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
  echo "❌ WARNING: Code injection detected! Expected: $EXPECTED_COMMIT, Actual: $ACTUAL_COMMIT"
  exit 1
else
  echo "✅ Commit verified - no code injection"
fi
```

#### 4\. Verify SBOM (Dependencies)

Lists all packages and dependencies in the image for vulnerability scanning.

```bash
cosign verify-attestation \
  --type spdx \
  --certificate-identity-regexp='https://github.com/fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0 \
  | jq '.payload | @base64d | fromjson | .predicate'
```

## Dockerfile Requirements

For the workflow to meet SLSA L3 and ensure build reproducibility, Dockerfiles must follow best practices:

  * **Multi-Stage Builds**: Separate build and runtime environments.
  * **Pin Base Images by Digest**: Use `FROM image:tag@sha256:...` to guarantee the same base image is used every time.
  * **Non-Root User**: Use `USER` to run the application as a non-root user for reduced privilege.
  * **BuildKit Cache Mounts**: Use `--mount=type=cache,target=/path` for optimized and reproducible caching.
  