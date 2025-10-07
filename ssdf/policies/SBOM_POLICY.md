# Software Bill of Materials (SBOM) Policy
## DevSecOps Platform SBOM Generation, Management, and Distribution

**Policy Version:** 1.0
**Effective Date:** 2025-10-07
**Review Frequency:** Annual
**Policy Owner:** Chief Information Security Officer (CISO)
**Technical Owner:** DevSecOps Engineering Manager
**Classification:** Public

---

## 1. PURPOSE AND SCOPE

### 1.1 Purpose

This policy establishes requirements for generating, managing, and distributing Software Bills of Materials (SBOMs) for all software produced and deployed by [Organization Name]. SBOMs provide transparency into software composition, enabling vulnerability management, license compliance, and supply chain risk management.

### 1.2 Scope

This policy applies to:
- All internally developed software applications
- Container images deployed to production
- Infrastructure as Code (IaC) configurations
- Build artifacts and release packages
- Third-party software components integrated into our products

### 1.3 Regulatory and Framework Alignment

This policy supports compliance with:
- **Executive Order 14028** "Improving the Nation's Cybersecurity" (Section 4e)
- **NIST SP 800-218 SSDF** Practice PW.9.1 (Create and maintain SBOM)
- **NIST SP 800-161 Rev. 1** C-SCRM for Federal Information Systems
- **NTIA Minimum Elements for SBOM** (July 2021)
- **OMB M-22-18** Memorandum on Secure Software Development

---

## 2. SBOM REQUIREMENTS

### 2.1 When to Generate SBOMs

**REQUIRED for:**
- Every production container image build
- Every software release (semantic versioned tags)
- Infrastructure as Code deployments (Terraform, Packer images)
- Third-party component procurement and integration

**OPTIONAL for:**
- Development and test builds (recommended for consistency)
- Internal tools and utilities (recommended)

**Generation Trigger:** Automated in CI/CD pipeline at build completion

### 2.2 SBOM Format Standards

**Primary Format: SPDX (Software Package Data Exchange)**
- Standard: SPDX 2.3 (ISO/IEC 5962:2021)
- Serialization: JSON (primary), YAML (alternate)
- File naming: `sbom-<product>-<version>.spdx.json`
- Example: `sbom-devsecops-platform-v1.0.0.spdx.json`

**Alternate Format: CycloneDX**
- Standard: CycloneDX 1.5
- Serialization: JSON (primary), XML (alternate)
- File naming: `sbom-<product>-<version>.cdx.json`
- Use case: Compatibility with specific tooling (e.g., Dependency-Track)

**Format Selection Priority:**
1. SPDX 2.3 JSON (default for all builds)
2. CycloneDX 1.5 JSON (generated in addition to SPDX)
3. Both formats signed and attested with Cosign

### 2.3 NTIA Minimum Elements

All SBOMs MUST include the following minimum elements as defined by NTIA:

#### Baseline SBOM Elements

**1. Supplier Name**
- Component supplier/vendor name
- Example: "Apache Software Foundation", "Google", "Internal Development"

**2. Component Name**
- Canonical name of the component
- Example: "log4j-core", "nginx", "devsecops-platform"

**3. Version of the Component**
- Specific version identifier (semantic versioning preferred)
- Example: "2.17.1", "1.21.0", "v1.0.0"

**4. Other Unique Identifiers**
- Package URL (purl): `pkg:type/namespace/name@version`
- CPE (Common Platform Enumeration): `cpe:2.3:a:vendor:product:version`
- Example purl: `pkg:npm/lodash@4.17.21`
- Example CPE: `cpe:2.3:a:apache:log4j:2.17.1:*:*:*:*:*:*:*`

**5. Dependency Relationships**
- Direct dependencies (top-level)
- Transitive dependencies (dependencies of dependencies)
- Relationship type: DEPENDS_ON, BUILD_DEPENDENCY, TEST_DEPENDENCY

**6. Author of SBOM Data**
- SBOM creator: "DevSecOps Platform CI/CD Pipeline"
- Creator tool: "Syft v0.92.0"
- Timestamp: ISO 8601 format (UTC)

**7. Timestamp**
- SBOM generation timestamp
- Format: `2025-10-07T14:32:15Z`

#### Additional Elements (Organization-Specific)

**8. Component Hash**
- SHA-256 hash of component artifact
- Purpose: Integrity verification

**9. License Information**
- SPDX License Identifier (e.g., MIT, Apache-2.0, GPL-3.0)
- License URL for non-standard licenses

**10. Vulnerability Status**
- Known CVEs at time of SBOM generation
- Vulnerability scanning results reference

**11. Supplier Contact**
- Email or URL for security disclosures
- Example: security@vendor.com

**12. Source Location**
- Git repository URL and commit SHA
- Example: https://github.com/org/repo@abc123def456

### 2.4 Component Depth and Completeness

**Direct Dependencies:**
- All top-level components explicitly declared in manifest files
- Examples: package.json (npm), requirements.txt (Python), go.mod (Go), pom.xml (Java)

**Transitive Dependencies:**
- All dependencies of direct dependencies (recursive)
- Depth: Unlimited (full dependency tree)
- Resolution: Based on lock files (package-lock.json, Pipfile.lock, go.sum, etc.)

**Operating System Packages:**
- All OS-level packages in container base images
- Detected via package manager databases (dpkg, rpm, apk)

**Excluded Components:**
- Development-only dependencies (excluded in production builds)
- Test frameworks and utilities (unless deployed)
- Build tools that don't end up in final artifact

---

## 3. SBOM GENERATION PROCESS

### 3.1 Automated Generation Tools

**Primary Tool: Syft**
- Version: 0.92.0 or later
- Developer: Anchore
- License: Apache 2.0
- Installation: Bundled in CI/CD runner environment

**Alternate Tools (for validation):**
- Trivy SBOM mode: `trivy image --format spdx-json`
- CycloneDX CLI: `cyclonedx-cli generate`

### 3.2 Generation Workflow

**Step 1: Build Artifact**
```yaml
# Example: Container build
- name: Build container image
  run: |
    docker build -t $IMAGE_NAME:$VERSION .
    docker save $IMAGE_NAME:$VERSION -o image.tar
```

**Step 2: Generate SBOM (SPDX 2.3)**
```yaml
- name: Generate SBOM with Syft
  run: |
    syft $IMAGE_NAME:$VERSION \
      --output spdx-json \
      --file sbom-$IMAGE_NAME-$VERSION.spdx.json

    # Verify SBOM has minimum elements
    jq -e '.name and .versionInfo and .creationInfo' sbom-*.spdx.json
```

**Step 3: Generate Alternate Format (CycloneDX)**
```yaml
- name: Generate CycloneDX SBOM
  run: |
    syft $IMAGE_NAME:$VERSION \
      --output cyclonedx-json \
      --file sbom-$IMAGE_NAME-$VERSION.cdx.json
```

**Step 4: Enrich SBOM with Vulnerability Data**
```yaml
- name: Scan for vulnerabilities
  run: |
    grype sbom:sbom-$IMAGE_NAME-$VERSION.spdx.json \
      --output json \
      --file vulnerability-report.json

    # Merge vulnerability data into SBOM
    jq --slurpfile vulns vulnerability-report.json \
      '.vulnerabilities = $vulns[0].matches' \
      sbom-$IMAGE_NAME-$VERSION.spdx.json > sbom-enriched.spdx.json
```

**Step 5: Sign and Attest SBOM**
```yaml
- name: Sign SBOM with Cosign
  env:
    COSIGN_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
  run: |
    # Sign the image
    cosign sign --key env://COSIGN_KEY $IMAGE_NAME:$VERSION

    # Attest the SBOM
    cosign attest \
      --key env://COSIGN_KEY \
      --predicate sbom-enriched.spdx.json \
      --type https://spdx.dev/Document \
      $IMAGE_NAME:$VERSION
```

**Step 6: Upload SBOM Artifacts**
```yaml
- name: Upload SBOM to artifact repository
  run: |
    # Upload to GCS
    gsutil cp sbom-*.spdx.json gs://sbom-repository/products/$IMAGE_NAME/$VERSION/
    gsutil cp sbom-*.cdx.json gs://sbom-repository/products/$IMAGE_NAME/$VERSION/

    # Upload to Gitea Actions artifacts
    - uses: actions/upload-artifact@v3
      with:
        name: sbom-${{ github.sha }}
        path: sbom-*.json
        retention-days: 90
```

### 3.3 Quality Assurance

**SBOM Validation Checks:**
1. **Schema validation**: Conform to SPDX 2.3 / CycloneDX 1.5 JSON schema
2. **Minimum elements**: All NTIA minimum elements present
3. **Component count**: Reasonable number of components (warn if <5 or >10,000)
4. **Unique identifiers**: All components have purl or CPE
5. **License data**: All components have license information
6. **No duplicates**: No duplicate component entries

**Validation Tool:**
```bash
# SPDX validation
spdx-tools validate sbom-*.spdx.json

# Custom validation script
python validate-sbom.py --sbom sbom-*.spdx.json --min-components 10
```

**Validation Failure Action:**
- Pipeline fails (exit code 1)
- Notification sent to DevSecOps team
- SBOM regenerated after fixing issues

---

## 4. SBOM MAINTENANCE AND UPDATES

### 4.1 Update Frequency

**Real-Time Updates:**
- New vulnerability discovered in component → SBOM regenerated with vulnerability data
- Component version updated → New SBOM generated for updated artifact

**Scheduled Updates:**
- **Daily**: Vulnerability data refresh for all production SBOMs
- **Weekly**: SBOM regeneration for long-running deployments (even if code unchanged)
- **Monthly**: SBOM audit and cleanup (remove obsolete versions)

### 4.2 SBOM Versioning

**SBOM Version Scheme:**
- SBOM version tied to artifact version (1:1 relationship)
- SBOM filename includes artifact version: `sbom-app-v1.2.3.spdx.json`
- Each SBOM update creates new timestamped version: `sbom-app-v1.2.3-updated-20251007.spdx.json`

**SBOM Revision Tracking:**
```json
{
  "creationInfo": {
    "created": "2025-10-07T14:32:15Z",
    "creators": ["Tool: syft-0.92.0", "Organization: Example Corp"],
    "licenseListVersion": "3.21",
    "comment": "Initial SBOM generation for v1.0.0 release"
  },
  "annotations": [
    {
      "annotationDate": "2025-10-08T10:15:00Z",
      "annotationType": "REVIEW",
      "annotator": "Person: security-team",
      "comment": "Updated with CVE-2025-12345 vulnerability data"
    }
  ]
}
```

### 4.3 SBOM Lifecycle

**Creation → Storage → Distribution → Archival → Deletion**

| Stage | Timing | Location | Retention |
|-------|--------|----------|-----------|
| **Creation** | Build time | CI/CD runner temporary storage | Until upload complete |
| **Storage (Hot)** | Post-build | GCS sbom-repository (Standard class) | 90 days |
| **Storage (Warm)** | 90 days | GCS (Nearline class) | 1 year |
| **Storage (Cold)** | 1 year | GCS (Archive class) | 7 years |
| **Deletion** | 7 years | Automatic GCS lifecycle policy | N/A |

**Special Retention:**
- Production release SBOMs: 7 years (regulatory requirement)
- Development build SBOMs: 90 days
- Deprecated product SBOMs: 3 years after end-of-life

---

## 5. SBOM DISTRIBUTION

### 5.1 Distribution Channels

**Primary Distribution: Public SBOM Repository**
- URL: https://sbom.example.com
- Protocol: HTTPS with TLS 1.3
- Authentication: Public read access (no authentication required)
- Format: Web UI + direct file download

**Alternate Channels:**
- **With Artifact**: SBOM bundled in container image as `/sbom/sbom.spdx.json`
- **API Access**: RESTful API for automated SBOM retrieval
- **On Request**: Email delivery for specific customer requests

### 5.2 Public SBOM Repository Structure

```
https://sbom.example.com/
├── products/
│   ├── devsecops-platform/
│   │   ├── v1.0.0/
│   │   │   ├── sbom-devsecops-platform-v1.0.0.spdx.json
│   │   │   ├── sbom-devsecops-platform-v1.0.0.cdx.json
│   │   │   ├── sbom.spdx.json.sig (Cosign signature)
│   │   │   └── README.md (version-specific notes)
│   │   ├── v1.0.1/
│   │   └── latest -> v1.0.1 (symlink)
│   ├── app-frontend/
│   └── app-backend/
├── base-images/
│   ├── ubuntu-22.04-hardened/
│   └── alpine-3.18-minimal/
└── index.html (web UI for browsing)
```

### 5.3 SBOM Access API

**Endpoint:** `https://api.sbom.example.com/v1/sbom`

**Authentication:** API key (optional for public SBOMs, required for customer-specific)

**Example API Request:**
```bash
# Get SBOM by product and version
curl https://api.sbom.example.com/v1/sbom/devsecops-platform/v1.0.0 \
  --output sbom.spdx.json

# Get latest SBOM for product
curl https://api.sbom.example.com/v1/sbom/devsecops-platform/latest \
  --output sbom-latest.spdx.json

# Search SBOMs by component
curl "https://api.sbom.example.com/v1/search?component=log4j&version=2.17.1"

# Get SBOM with vulnerability data
curl "https://api.sbom.example.com/v1/sbom/app/v2.0.0?include=vulnerabilities"
```

**Response Format:**
```json
{
  "product": "devsecops-platform",
  "version": "v1.0.0",
  "sbom_format": "spdx-2.3",
  "generated_at": "2025-10-07T14:32:15Z",
  "download_url": "https://sbom.example.com/products/devsecops-platform/v1.0.0/sbom.spdx.json",
  "signature_url": "https://sbom.example.com/products/devsecops-platform/v1.0.0/sbom.spdx.json.sig",
  "cosign_public_key": "https://sbom.example.com/cosign.pub",
  "components_count": 247,
  "vulnerabilities_count": 0
}
```

### 5.4 Customer-Specific SBOM Delivery

**Upon Request:**
- Customer submits request via email (sbom-request@example.com)
- SBOM delivered within 24 hours (SLA)
- Customer-specific format preferences honored (SPDX/CycloneDX)
- Includes verification instructions and Cosign public key

**Contract Requirements:**
- SBOMs provided as part of software license agreement
- Delivered with every major/minor release (within 48 hours)
- Security updates trigger automatic SBOM redistribution

---

## 6. SBOM SIGNING AND VERIFICATION

### 6.1 Digital Signatures

**Signing Method: Cosign (Sigstore)**
- Key type: ECDSA P-256
- Key storage: Google Cloud KMS
- Signature algorithm: SHA-256 with ECDSA

**Signing Process:**
```bash
# Sign SBOM file
cosign sign-blob \
  --key gcpkms://projects/${PROJECT_ID}/locations/us-central1/keyRings/cosign/cryptoKeys/sbom-signing \
  --output-signature sbom.spdx.json.sig \
  sbom.spdx.json

# Attest SBOM to container image
cosign attest \
  --key gcpkms://projects/${PROJECT_ID}/locations/us-central1/keyRings/cosign/cryptoKeys/sbom-signing \
  --predicate sbom.spdx.json \
  --type https://spdx.dev/Document \
  $IMAGE_NAME:$VERSION
```

### 6.2 Verification Instructions

**Public Key Distribution:**
- URL: https://sbom.example.com/cosign.pub
- Fingerprint: `SHA256:a4f3c2d1e5b6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2`

**Verification Steps:**
```bash
# 1. Download SBOM and signature
curl -O https://sbom.example.com/products/app/v1.0.0/sbom.spdx.json
curl -O https://sbom.example.com/products/app/v1.0.0/sbom.spdx.json.sig
curl -O https://sbom.example.com/cosign.pub

# 2. Verify signature with Cosign
cosign verify-blob \
  --key cosign.pub \
  --signature sbom.spdx.json.sig \
  sbom.spdx.json

# Expected output:
# Verified OK

# 3. Verify SBOM attestation on container image
cosign verify-attestation \
  --key cosign.pub \
  --type https://spdx.dev/Document \
  gcr.io/example/app:v1.0.0

# 4. Extract and view attested SBOM
cosign verify-attestation \
  --key cosign.pub \
  --type https://spdx.dev/Document \
  gcr.io/example/app:v1.0.0 | jq -r .payload | base64 -d | jq .predicate
```

---

## 7. VULNERABILITY DISCLOSURE IN SBOMs

### 7.1 Vulnerability Data Inclusion

**SBOM Vulnerability Section:**
- Known CVEs included in SBOM at generation time
- Vulnerability data source: NVD, OSV, GCP Security Command Center
- Severity: CVSS v3.1 score and vector
- Remediation status: FIXED, IN_PROGRESS, ACCEPTED, NOT_AFFECTED

**Example (SPDX with Vulnerability Extension):**
```json
{
  "SPDXID": "SPDXRef-Package-log4j-core-2.17.0",
  "name": "log4j-core",
  "versionInfo": "2.17.0",
  "externalRefs": [
    {
      "referenceCategory": "SECURITY",
      "referenceType": "cpe23Type",
      "referenceLocator": "cpe:2.3:a:apache:log4j:2.17.0:*:*:*:*:*:*:*"
    },
    {
      "referenceCategory": "SECURITY",
      "referenceType": "advisory",
      "referenceLocator": "https://nvd.nist.gov/vuln/detail/CVE-2021-44228",
      "comment": "FIXED in version 2.17.1"
    }
  ],
  "annotations": [
    {
      "annotationDate": "2025-10-07T14:32:15Z",
      "annotationType": "REVIEW",
      "annotator": "Tool: grype-0.68.0",
      "comment": "No vulnerabilities found in this version"
    }
  ]
}
```

### 7.2 SBOM Updates on New Vulnerabilities

**Trigger:** New CVE announced for component in SBOM

**Action:**
1. Automated scan detects new CVE via daily vulnerability refresh
2. SBOM regenerated with updated vulnerability data
3. New SBOM version published with timestamp suffix
4. Notification sent to SBOM subscribers (if configured)
5. Original SBOM retained for historical record

**Notification Example:**
```
Subject: SBOM Update: New vulnerability in devsecops-platform v1.0.0

A new vulnerability (CVE-2025-12345) has been discovered in a component
of devsecops-platform v1.0.0.

Component: log4j-core 2.17.0
CVE: CVE-2025-12345
Severity: HIGH (CVSS 7.5)
Status: Patch available (upgrade to 2.17.2)

Updated SBOM:
https://sbom.example.com/products/devsecops-platform/v1.0.0/sbom-updated-20251007.spdx.json

Remediation timeline: 72 hours (per vulnerability management policy)
```

---

## 8. THIRD-PARTY SBOM REQUIREMENTS

### 8.1 Vendor SBOM Expectations

All third-party software vendors must provide SBOMs meeting:
- **Format**: SPDX 2.3 or CycloneDX 1.5 (JSON)
- **Elements**: NTIA minimum elements (see Section 2.3)
- **Delivery**: Within 48 hours of software delivery
- **Updates**: Updated SBOM on every patch/update

### 8.2 SBOM Acceptance Criteria

**Pre-Acceptance Validation:**
1. SBOM schema validation (SPDX/CycloneDX conformance)
2. Minimum elements check (all NTIA elements present)
3. Component count reasonableness (not suspiciously low)
4. License data completeness (all components licensed)
5. Signature verification (if signed by vendor)

**Rejection Reasons:**
- Invalid SBOM format or schema
- Missing required elements (e.g., no component versions)
- Suspected incomplete component list
- Unlicensed components or license conflicts

**Vendor Notification on Rejection:**
```
Your SBOM for [Product] version [Version] has been rejected.

Reason: Missing dependency information (only 5 components listed,
expected 50+ based on package size analysis).

Required action:
1. Regenerate SBOM with complete dependency tree (including transitive deps)
2. Include all NTIA minimum elements
3. Resubmit within 72 hours

Tool recommendation: Use Syft or CycloneDX CLI for comprehensive SBOM generation.
```

### 8.3 Vendor SBOM Storage

**Location:** `/vendor-sboms/[vendor-name]/[product]/[version]/`

**Structure:**
```
/vendor-sboms/
├── apache/
│   └── log4j/
│       ├── 2.17.0/
│       │   ├── sbom-log4j-2.17.0.spdx.json (vendor-provided)
│       │   ├── sbom-log4j-2.17.0-validated.json (our validation)
│       │   └── acceptance-date.txt (2025-09-15)
│       └── 2.17.1/
├── ubuntu/
│   └── base-image/
│       └── 22.04/
└── google/
    └── distroless/
```

---

## 9. SBOM SECURITY AND ACCESS CONTROL

### 9.1 SBOM Confidentiality

**Public SBOMs:**
- Production release SBOMs are PUBLIC by default
- Distributed without authentication
- Indexed by search engines (intentional for transparency)

**Internal SBOMs:**
- Development builds: INTERNAL (authenticated access only)
- Pre-release candidates: INTERNAL until release
- Customer-specific builds: CONFIDENTIAL (customer-only access)

**Sensitive Component Redaction:**
- Internal tool names may be redacted in public SBOMs
- Proprietary component versions may be generalized
- Customer-specific customizations redacted

### 9.2 Access Control

**Public SBOM Repository:**
- No authentication required for read access
- HTTPS only (TLS 1.3)
- Rate limiting: 1000 requests/hour per IP

**Internal SBOM Storage (GCS):**
- IAM-controlled access
- Read access: DevSecOps Engineers, Security Champions, Compliance Auditors
- Write access: CI/CD service accounts only
- No delete access (append-only for audit trail)

**SBOM API:**
- API key required for non-public SBOMs
- Rate limiting: 100 requests/minute per key
- Usage logged for audit

---

## 10. TRAINING AND AWARENESS

### 10.1 SBOM Training Requirements

**DevSecOps Engineers:**
- SBOM format standards (SPDX, CycloneDX)
- SBOM generation tools (Syft, Trivy)
- SBOM signing and verification (Cosign)
- Frequency: Annual + on tool updates

**Developers:**
- Understanding SBOM purpose and benefits
- How to request SBOMs for third-party components
- Interpreting SBOM vulnerability data
- Frequency: Annual security awareness training

**Procurement:**
- SBOM requirements in vendor contracts
- Vendor SBOM acceptance criteria
- Escalation procedures for non-compliant vendors
- Frequency: Annual + on policy updates

### 10.2 Documentation

**Internal Documentation:**
- SBOM Generation Guide (for developers)
- SBOM Verification Guide (for security team)
- Vendor SBOM Acceptance Procedures (for procurement)

**External Documentation:**
- Public SBOM Repository User Guide (https://sbom.example.com/docs)
- SBOM Verification Instructions (for customers)
- SBOM Request Process (for partners)

---

## 11. METRICS AND REPORTING

### 11.1 SBOM Generation Metrics

| Metric | Target | Actual (Last 30 Days) | Status |
|--------|--------|----------------------|--------|
| SBOM generation success rate | 100% | 99.2% | MEETS |
| Average SBOM generation time | <2 minutes | 1.3 minutes | EXCEEDS |
| SBOMs signed/attested | 100% | 100% | MEETS |
| SBOM validation failures | <1% | 0.8% | MEETS |
| Vendor SBOMs received on time | 95% | 92% | BELOW (Action: vendor outreach) |

### 11.2 SBOM Distribution Metrics

| Metric | Value (Last 30 Days) |
|--------|---------------------|
| Public SBOM downloads | 1,247 |
| API requests | 3,421 |
| Customer SBOM requests | 12 |
| Average delivery time (customer requests) | 8 hours |
| SBOM verification failures | 0 |

### 11.3 Vulnerability Tracking via SBOM

- Components tracked across all SBOMs: 12,453 unique
- SBOMs requiring updates due to new CVEs: 23 (last 30 days)
- Average time from CVE publication to SBOM update: 6 hours
- SBOMs with critical vulnerabilities: 0

---

## 12. POLICY GOVERNANCE

### 12.1 Policy Review

- **Frequency**: Annual (October)
- **Triggered Review**: Upon regulatory changes, framework updates, or major incidents
- **Reviewers**: CISO, DevSecOps Manager, Compliance Officer
- **Approval**: CISO signature required

### 12.2 Policy Exceptions

**Exception Request Process:**
1. Submit exception request via security ticket (Taiga)
2. Justification with business impact and compensating controls
3. Security Champion review (5 business days)
4. CISO approval required for exceptions >30 days
5. Documented in exception log with expiration date

**Current Active Exceptions:** None

### 12.3 Policy Violations

**Violation Examples:**
- SBOM not generated for production release
- SBOM missing required NTIA elements
- SBOM not signed before distribution
- Vendor SBOM not obtained before deployment

**Consequences:**
- Minor violation (first occurrence): Warning + remediation
- Repeat violation: Escalation to management
- Critical violation: Deployment blocked, incident investigation

---

## 13. REFERENCES

### 13.1 Standards and Frameworks

- NIST SP 800-218: Secure Software Development Framework (SSDF)
- NTIA: "The Minimum Elements for a Software Bill of Materials (SBOM)" (July 2021)
- SPDX 2.3 Specification: https://spdx.github.io/spdx-spec/v2.3/
- CycloneDX 1.5 Specification: https://cyclonedx.org/specification/overview/
- ISO/IEC 5962:2021 SPDX Standard
- Executive Order 14028 Section 4(e)

### 13.2 Tools and Resources

- Syft: https://github.com/anchore/syft
- Cosign: https://github.com/sigstore/cosign
- SPDX Tools: https://github.com/spdx/tools
- CycloneDX CLI: https://github.com/CycloneDX/cyclonedx-cli

### 13.3 Related Policies

- Vulnerability Disclosure Policy (VULNERABILITY_DISCLOSURE_POLICY.md)
- Secure Development Policy (SECURE_DEVELOPMENT_POLICY.md)
- Third-Party Software Management Policy (THIRD_PARTY_SOFTWARE_POLICY.md)

---

## DOCUMENT APPROVAL

**Policy Owner:**
- Name: [CISO Name]
- Title: Chief Information Security Officer
- Signature: _________________________________
- Date: 2025-10-07

**Technical Owner:**
- Name: [DevSecOps Manager Name]
- Title: DevSecOps Engineering Manager
- Signature: _________________________________
- Date: 2025-10-07

**Legal Review:**
- Name: [Legal Counsel Name]
- Title: General Counsel
- Signature: _________________________________
- Date: 2025-10-07

---

**Next Review Date:** 2026-10-07

**Version History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-07 | DevSecOps Team | Initial policy based on NIST SSDF PW.9 requirements |

---

**END OF POLICY**
