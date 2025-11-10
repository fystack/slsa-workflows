# SLSA Level 3 Workflows Template

Enterprise-grade reusable GitHub Actions workflows for building, signing, and generating SLSA Level 3 provenance attestation for Docker images.

## Features

- **SLSA Level 3 Compliance**: Non-forgeable provenance generation using official `slsa-framework/slsa-github-generator`
- **Keyless Signing**: Automatic signing with GitHub OIDC (no key management required)
- **Transparency**: Signatures recorded in Rekor public transparency log
- **SBOM Generation**: Optional Software Bill of Materials generation
- **Multi-Registry**: Supports Docker Hub, GHCR, and GCR
- **Build Caching**: Optimized builds with registry-based caching
- **Enterprise Ready**: Security best practices, non-root users, reproducible builds

## Workflow: `docker-build-slsa.yml`

### Overview

This workflow performs:
1. **Build**: Docker image build with BuildKit optimizations
2. **Push**: Push to container registry with multiple tags
3. **SBOM**: Generate Software Bill of Materials (optional)
4. **Provenance**: Generate SLSA L3 provenance in isolated job
5. **Sign**: Keyless signing with Cosign via GitHub OIDC
6. **Publish**: Attach attestations to registry

### Usage

#### Basic Example

```yaml
name: Release
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read

jobs:
  build:
    permissions:
      contents: read
      packages: write
      id-token: write
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

#### Advanced Example with Multiple Services

```yaml
jobs:
  build-api:
    uses: fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@main
    with:
      image-name: myorg/myapp-api
      context-path: services/api
      dockerfile: Dockerfile
      platforms: linux/amd64,linux/arm64
      build-args: |
        NODE_ENV=production
        API_VERSION=2.0
      enable-sbom: true
    secrets:
      registry-username: ${{ secrets.DOCKER_USERNAME }}
      registry-password: ${{ secrets.DOCKER_TOKEN }}

  build-worker:
    uses: fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@main
    with:
      image-name: myorg/myapp-worker
      context-path: services/worker
      dockerfile: Dockerfile
      registry: ghcr
    secrets:
      registry-username: ${{ github.actor }}
      registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image-name` |  | - | Full Docker image name (e.g., `fystack/apex-api`) |
| `context-path` |  | - | Build context path relative to repository root |
| `dockerfile` |  | - | Path to Dockerfile relative to context |
| `platforms` | L | `linux/amd64` | Target platforms (comma-separated) |
| `build-args` | L | `''` | Build arguments (newline-separated `KEY=VALUE` pairs) |
| `registry` | L | `dockerhub` | Container registry: `dockerhub`, `ghcr`, or `gcr` |
| `enable-sbom` | L | `true` | Generate SBOM attestation |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `registry-username` |  | Registry username (Docker Hub username, GitHub actor, etc.) |
| `registry-password` |  | Registry password or token |

### Outputs

| Output | Description |
|--------|-------------|
| `image-digest` | SHA256 digest of the built image |
| `image-uri` | Full image URI with digest (e.g., `myorg/myapp@sha256:abc...`) |

### Generated Tags

The workflow automatically generates the following tags:
- `{version}` - Git tag or branch name (e.g., `v1.0.0`)
- `{short-sha}` - First 7 characters of commit SHA
- `latest` - Always points to the most recent build

Example:
```
fystack/apex-api:v1.0.0
fystack/apex-api:a1b2c3d
fystack/apex-api:latest
```

## Dockerfile Requirements

To work seamlessly with this workflow, your Dockerfiles should:

### 1. Use Multi-Stage Builds
```dockerfile
# syntax=docker/dockerfile:1.4

FROM golang:1.24.4-alpine AS builder
# ... build steps

FROM alpine:3.21
# ... runtime
```

### 2. Accept Build Arguments
```dockerfile
ARG VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
ARG TARGETOS=linux
ARG TARGETARCH=amd64
```

### 3. Use BuildKit Cache Mounts
```dockerfile
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

RUN --mount=type=cache,target=/root/.cache/go-build \
    go build -o app ./cmd/app
```

### 4. Pin Base Images by Digest
```dockerfile
FROM golang:1.24.4-alpine@sha256:68932fa6d4d4059845c8f40ad7e654e626f3ebd3706eef7846f319293ab5cb7a
FROM alpine:3.21@sha256:5405e8f36ce1878720f71217d664aa3dea32e5e5df11acbf07fc78ef5661465b
```

### 5. Run as Non-Root User
```dockerfile
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

USER appuser:appuser
```

## Verifying SLSA Attestations

After the workflow completes, you can verify the attestations:

### Verify Signature

```bash
cosign verify \
  --certificate-identity-regexp='https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/.*@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0
```

### Verify SLSA Provenance

```bash
slsa-verifier verify-image \
  myorg/myapp:v1.0.0 \
  --source-uri github.com/YOUR_ORG/YOUR_REPO \
  --source-tag v1.0.0
```

### Inspect Provenance

```bash
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp='https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/.*@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0 | jq '.payload | @base64d | fromjson'
```

### Inspect SBOM

```bash
cosign verify-attestation \
  --type spdx \
  --certificate-identity-regexp='https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/.*@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0 | jq '.payload | @base64d | fromjson'
```

## Security Considerations

### SLSA Level 3 Requirements

This workflow meets SLSA L3 requirements:

-  **Build platform**: GitHub Actions with hardened runner
-  **Build isolation**: SLSA generator runs in separate, non-privileged job
-  **Provenance**: Non-forgeable, automatically generated
-  **Hermetic**: Build dependencies pinned by digest
-  **Reproducible**: Deterministic builds with BuildKit
-  **Parameterless**: No user-controlled build parameters in provenance

### Best Practices

1. **Pin Base Images**: Always use digest-pinned base images
2. **Minimal Runtime**: Use distroless or Alpine for minimal attack surface
3. **Non-Root**: Run containers as non-root user
4. **SBOM Enabled**: Always generate SBOM for vulnerability scanning
5. **Private Registries**: Use private registries for internal images
6. **Branch Protection**: Require PR reviews before merging to main/release branches

## Troubleshooting

### Build Fails with "permission denied"

Ensure your Dockerfile copies files with correct ownership:
```dockerfile
COPY --from=builder --chown=appuser:appuser /app/binary .
```

### Provenance Generation Fails

Check that the calling workflow has correct permissions:
```yaml
permissions:
  contents: read
  packages: write
  id-token: write
  actions: read
```

### Registry Authentication Fails

For Docker Hub:
- Use your Docker Hub username (not email)
- Use an access token (not password)
- Store in GitHub Secrets: `DOCKER_USERNAME` and `DOCKER_TOKEN`

For GHCR:
- Use `${{ github.actor }}` as username
- Use `${{ secrets.GITHUB_TOKEN }}` as password

## Examples

See real-world examples in:
- [`apex/.github/workflows/release.yml`](../apex/.github/workflows/release.yml) - Multi-service release workflow
- [`apex/deployments/api/Dockerfile`](../apex/deployments/api/Dockerfile) - Enterprise-grade Dockerfile with CGO
- [`apex/deployments/rescanner/Dockerfile`](../apex/deployments/rescanner/Dockerfile) - Optimized static binary

## References

- [SLSA Framework](https://slsa.dev/)
- [SLSA GitHub Generator](https://github.com/slsa-framework/slsa-github-generator)
- [Sigstore Cosign](https://github.com/sigstore/cosign)
- [BuildKit](https://github.com/moby/buildkit)
- [OCI Image Spec](https://github.com/opencontainers/image-spec)

## License

See individual project licenses in the monorepo.
