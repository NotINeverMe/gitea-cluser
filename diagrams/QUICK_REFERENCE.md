# Quick Reference - Gitea DevSecOps Security Diagrams

**Generated:** 2025-10-05
**Run ID:** 20251005_160510

---

## File Manifest

### Diagram Sources (13 files)
- `authorization-boundary.mmd` (7.1 KB) - Mermaid ABD
- `authorization-boundary.puml` (6.3 KB) - PlantUML ABD
- `data-flow.mmd` (6.8 KB) - Mermaid DFD
- `data-flow.puml` (7.4 KB) - PlantUML DFD
- `network-topology.mmd` (5.5 KB) - Mermaid network diagram
- `evidence-flow.mmd` (5.5 KB) - Mermaid evidence flow

### Data Files (2 files)
- `ASSET_INVENTORY.csv` (5.2 KB) - **26 assets** catalogued
- `FLOW_INVENTORY.csv` (8.4 KB) - **52 flows** catalogued

### Documentation (4 files)
- `README.md` (17 KB) - Overview, assumptions, control mapping
- `VALIDATION_CHECKLIST.md` (22 KB) - Assessor validation checklist
- `DIAGRAM_GENERATION.md` (13 KB) - Rendering instructions
- `QUICK_REFERENCE.md` - This file

### Scripts (2 files)
- `render-mermaid.sh` (2.7 KB) - Render all Mermaid diagrams
- `render-plantuml.sh` (2.3 KB) - Render all PlantUML diagrams

**Total:** 2,586 lines across all files

---

## Asset Summary (26 Total)

### By CMMC Category
- **[CUI]** - 2 assets (A-6: Gitea, S-1: Gitea DB)
- **[SPA]** - 10 assets (Proxy, VPN, n8n, SonarQube, Prometheus, Grafana, 4 DBs)
- **[CRMA]** - 1 asset (S-5: GCS Evidence Bucket)
- **[SPC]** - 7 assets (All security scanners)
- **[OOS]** - 1 asset (A-1: End Users)
- **[External]** - 5 assets (GCP APIs, registries, SCC, CAI, Logging, Chat)

### By Trust Zone
- **Z-1 (Internet):** 3 assets
- **Z-2 (DMZ):** 2 assets
- **Z-3 (Application):** 5 assets
- **Z-4 (Data):** 4 assets
- **Z-5 (Scanning):** 7 assets
- **Z-6 (GCP Cloud):** 5 assets

---

## Flow Summary (52 Total)

### By Use Case
1. **Code Commit & Scanning:** F-1, F-11, F-15, F-21-23, F-28-29, F-36-38 (11 flows)
2. **SAST Integration:** F-16, F-12, F-39 (3 flows)
3. **IaC Security:** F-40-45 (6 flows)
4. **Evidence Collection:** F-46-48, F-30, F-13 (5 flows)
5. **GCP Integration:** F-31-32, F-35 (3 flows)
6. **Audit Logging:** F-33, F-49 (2 flows)
7. **Notifications:** F-34 (1 flow)
8. **Monitoring:** F-17-20, F-14, F-50 (6 flows)
9. **Admin Access:** F-4, F-9-10, F-51-52 (5 flows)
10. **DMZ Routing:** F-2-3, F-5-8 (6 flows)

### By Protocol
- **HTTPS/443:** 18 flows (All GCP, external, and web UI)
- **SSH/22:** 6 flows (Git, admin access)
- **HTTP/Internal:** 12 flows (Inter-service communication)
- **PostgreSQL/5432:** 3 flows (Database connections)
- **Docker Socket:** 7 flows (Container orchestration)
- **In-Process:** 2 flows (Evidence hashing, control mapping)
- **Other:** 4 flows (WireGuard, Prometheus scraping, local write)

### By Encryption
- **TLS 1.3:** 24 flows
- **SSH Encryption:** 6 flows
- **AES-256-GCM (at rest):** 8 flows
- **WireGuard:** 1 flow
- **Internal/Unix Socket:** 13 flows

---

## Trust Boundary Crossings

### Internet → DMZ (4 flows)
- F-1: HTTPS/443 → Reverse Proxy
- F-2: SSH/22 → Reverse Proxy (Git)
- F-3: HTTPS/443 → Reverse Proxy (Registry)
- F-4: WireGuard/51820 → VPN Gateway

### DMZ → Application (6 flows)
- F-5: HTTP/3000 (Gitea UI)
- F-6: HTTP/5678 (n8n UI)
- F-7: HTTP/9000 (SonarQube UI)
- F-8: HTTP/3001 (Grafana UI)
- F-9: SSH/Admin (Gitea)
- F-10: SSH/Admin (n8n)

### Application → GCP Cloud (9 flows)
- F-30: Evidence upload to GCS
- F-31: Query SCC
- F-32: Query Cloud Asset Inventory
- F-33: Audit logs to Cloud Logging
- F-34: Google Chat notifications
- F-48: Compliance manifest to GCS
- F-49: Gitea logs to Cloud Logging
- F-35: SCC findings → n8n (reverse)

### Scanning → Internet (2 flows)
- F-28: Trivy CVE DB update
- F-29: Grype CVE DB update

---

## Control Mapping Quick Lookup

### NIST SP 800-171 Rev. 2 (25 controls addressed)

| Control | Name | Assets | Flows |
|---------|------|--------|-------|
| **3.1.1** | Access Control | A-4, A-5, A-6, A-7 | F-5 through F-10, F-15, F-16, F-20 |
| **3.1.12** | Remote Access | A-5 (VPN) | F-4, F-9, F-10, F-51, F-52 |
| **3.1.20** | External Connections | A-2 (GCP APIs) | F-28 through F-35 |
| **3.3.1** | Audit Creation | A-9 (Prometheus), A-20 (Logging) | F-17, F-18, F-19, F-33, F-49 |
| **3.3.9** | Audit Protection | S-5 (GCS Immutable) | F-30, F-48 |
| **3.4.2** | Security Config | A-14, A-15, A-16 | F-42, F-43, F-44 |
| **3.5.3** | MFA | A-5 (VPN) | F-4, F-50, F-51, F-52 |
| **3.8.1** | Media Protection | S-5 (GCS CMEK) | F-30, F-48 |
| **3.11.2** | Vuln Scanning | A-11, A-12, A-13, A-18 | F-21, F-22, F-23, F-31 |
| **3.13.8** | Transmission Confidentiality | All HTTPS flows | F-2, F-30, F-31, F-33, F-34, F-35 |
| **3.13.11** | Cryptographic Protection | All encrypted assets | F-11, F-12, F-13, F-30, F-46 |
| **3.13.16** | Data at Rest | S-1, S-2, S-3, S-4, S-5 | All DB writes, GCS uploads |
| **3.14.1** | Flaw Remediation | A-11 through A-16 | F-21 through F-27, F-36 through F-44 |

### CMMC 2.0 Practices (24 practices)

| Practice ID | Name | Evidence |
|-------------|------|----------|
| **AC.L2-3.1.1** | Access Control | Authentication on all flows |
| **AU.L2-3.3.1** | Audit Logging | Prometheus + Cloud Logging |
| **AU.L2-3.3.9** | Audit Protection | GCS immutable storage |
| **SC.L2-3.13.8** | Transmission Confidentiality | TLS 1.3 on all HTTPS |
| **SC.L2-3.13.11** | Cryptographic Mechanisms | AES-256-GCM at rest |
| **SC.L2-3.13.16** | Data at Rest Protection | Encrypted volumes + GCS |
| **SI.L2-3.14.1** | Flaw Remediation | 7 security scanners |
| **IA.L2-3.5.3** | MFA | VPN + Admin access |
| **RA.L2-3.11.2** | Vulnerability Scanning | Continuous scanning |

---

## Network Topology Quick Facts

### IP Address Allocation
- **DMZ:** 10.10.1.0/24 (Reverse Proxy: .10, VPN: .5)
- **Application:** 10.10.2.0/24 (Gitea: .10, n8n: .20, SonarQube: .30)
- **Monitoring:** 10.10.5.0/24 (Prometheus: .10, Grafana: .20)
- **Data:** 10.10.3.0/24 (PG-Gitea: .10, PG-Sonar: .20, PG-n8n: .30, TSDB: .40)
- **Scanning:** 10.10.4.0/24 (Dynamic IPs, ephemeral)

### Firewall Rules Summary
1. **ACCEPT:** 443/tcp → 10.10.1.10 (Reverse proxy)
2. **ACCEPT:** 51820/udp → 10.10.1.5 (VPN)
3. **ACCEPT:** Established/Related
4. **DROP:** All other ingress
5. **ACCEPT:** Internal (10.10.0.0/16 ↔ 10.10.0.0/16)
6. **REJECT:** Data tier (10.10.3.0/24) → Internet
7. **ACCEPT:** Scan tier (10.10.4.0/24) → GCP APIs only

### Docker Networks
- `dmz-network` (10.10.1.0/24) - Bridge to host firewall
- `app-tier` (10.10.2.0/24) - Internal, no direct Internet
- `monitoring` (10.10.5.0/24) - Internal, scrape access to app-tier
- `data-tier` (10.10.3.0/24) - Fully isolated, ingress only from app-tier
- `scan-tier` (10.10.4.0/24) - Ephemeral, egress to GCP only

---

## Evidence Flow Quick Facts

### Storage Paths
1. **Raw Evidence:** `gs://evidence-bucket/raw/YYYY/MM/DD/HH/{timestamp}-{hash}.json`
2. **Manifests:** `gs://evidence-bucket/manifests/YYYY/MM/{timestamp}-manifest.json`
3. **Control Mapping:** `gs://evidence-bucket/controls/NIST-800-171/{control-id}/{timestamp}-evidence.json`

### Retention & Compliance
- **Retention:** 7 years (2,555 days)
- **Immutability:** Object Lock enabled (non-deletable)
- **Encryption:** CMEK AES-256-GCM
- **Versioning:** Enabled (all versions retained)
- **Integrity:** SHA-256 hash validation on upload and retrieval

### Evidence Pipeline
1. **Scanners** → JSON results → n8n
2. **n8n** → Enrich metadata (timestamp, commit SHA, repo, branch)
3. **n8n** → Generate SHA-256 hash
4. **n8n** → Map findings to NIST 800-171 controls
5. **n8n** → Upload to GCS (TLS 1.3 + OAuth2)
6. **GCS** → Apply lifecycle policy (7-year retention + immutable lock)
7. **n8n** → Generate manifest (catalog of all evidence)
8. **Cloud Logging** → Record all upload/access events

---

## Rendering Commands (Quick Start)

### Mermaid (Recommended)
```bash
cd /home/notme/Desktop/gitea/diagrams
./render-mermaid.sh
```

### PlantUML
```bash
cd /home/notme/Desktop/gitea/diagrams
./render-plantuml.sh
```

### Docker (Mermaid)
```bash
docker run --rm -v $(pwd):/data minlag/mermaid-cli \
  -i /data/authorization-boundary.mmd \
  -o /data/rendered/authorization-boundary.png \
  -w 4096 -H 2304
```

### Output
All rendered images saved to: `/home/notme/Desktop/gitea/diagrams/rendered/`

---

## Validation Steps (Top 5)

1. **Asset Completeness:** Verify all 26 assets in diagrams match `ASSET_INVENTORY.csv`
2. **Flow Completeness:** Verify all 52 flows in diagrams match `FLOW_INVENTORY.csv`
3. **Encryption Coverage:** Ensure all CUI flows have TLS 1.3 or SSH encryption
4. **Trust Boundaries:** Confirm all Internet/GCP crossings have authentication
5. **Control Mapping:** Cross-reference control claims with SSP implementation statements

Full checklist: See `VALIDATION_CHECKLIST.md` (10 sections, 100+ checkpoints)

---

## Common Assessor Questions

### Q: How is CUI protected at rest?
**A:** All databases use AES-256-GCM encryption via LUKS volumes (S-1, S-2, S-3, S-4). GCS evidence bucket (S-5) uses CMEK AES-256-GCM. References: §3.13.16, SC.L2-3.13.16.

### Q: How is CUI protected in transit?
**A:** TLS 1.3 for all HTTPS (F-2, F-30, F-31, F-33), SSH encryption for Git (F-1, F-40), WireGuard for VPN (F-4). No cleartext CUI transmission. References: §3.13.8, SC.L2-3.13.8.

### Q: How are vulnerabilities detected?
**A:** Trivy (A-11) for container CVEs, Grype (A-12) for SBOM analysis, Semgrep (A-13) for SAST, SonarQube (A-8) for code quality, Checkov/tfsec/Terrascan (A-14/15/16) for IaC. GCP SCC (A-18) aggregates findings. References: §3.11.2, RA.L2-3.11.2.

### Q: How is evidence protected from tampering?
**A:** SHA-256 hashing before upload (F-46), GCS Object Lock (immutable), 7-year retention policy, Cloud Audit Logs track all access. References: §3.3.9, AU.L2-3.3.9.

### Q: How is administrative access controlled?
**A:** VPN with MFA required (F-4), certificate-based SSH (F-51, F-52), no direct Internet access to admin interfaces. All admin actions logged to Cloud Logging (F-33, F-49). References: §3.1.12, §3.5.3, AC.L2-3.1.12, IA.L2-3.5.3.

---

## Troubleshooting

### Diagram won't render
- **Mermaid:** Check syntax with https://mermaid.live/
- **PlantUML:** Check syntax with https://www.plantuml.com/plantuml/
- **Large diagrams:** Increase size limit (`-DPLANTUML_LIMIT_SIZE=16384` for PlantUML)

### CSV won't import
- **Excel:** Save as UTF-8 CSV
- **LibreOffice:** Import with UTF-8 encoding, comma delimiter

### Missing control mapping
- **Check:** `ASSET_INVENTORY.csv` column "NIST_800-171_Controls"
- **Check:** `FLOW_INVENTORY.csv` column "NIST_800-171_Controls"
- **Reference:** `README.md` section "Control Coverage Summary"

---

## Contact Information

**Questions about diagrams:** See `README.md` for system owner contacts
**Questions about rendering:** See `DIAGRAM_GENERATION.md`
**Questions about validation:** See `VALIDATION_CHECKLIST.md`

---

**End of Quick Reference**
