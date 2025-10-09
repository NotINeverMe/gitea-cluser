# Atlantis + Terragrunt GitOps Implementation

## Production-Ready Infrastructure as Code with CMMC 2.0 & NIST SP 800-171 Compliance

This implementation provides a complete GitOps workflow for managing GCP infrastructure using Atlantis and Terragrunt with comprehensive security gates, policy enforcement, and compliance evidence collection.

## Quick Start

```bash
# 1. Run the automated setup
make setup

# 2. Configure GCP resources (replace with your project ID)
make setup-gcp PROJECT_ID=your-gcp-project

# 3. Start Atlantis
make start

# 4. Check status
make status
```

## Implementation Overview

### Complete File Structure

```
/home/notme/Desktop/gitea/
├── Makefile                                    # Automation commands
├── atlantis/
│   ├── docker-compose-atlantis.yml            # Atlantis stack deployment
│   ├── atlantis.yaml                          # Server configuration
│   ├── repos.yaml                             # Repository allowlist
│   ├── policies/
│   │   └── cmmc-nist.rego                     # OPA compliance policies
│   └── Caddyfile                              # TLS reverse proxy
├── terragrunt/
│   ├── terragrunt.hcl                         # Root configuration
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── env.hcl                        # Dev environment config
│   │   │   └── vpc/
│   │   │       └── terragrunt.hcl             # Dev VPC config
│   │   ├── staging/
│   │   │   └── env.hcl                        # Staging environment config
│   │   └── prod/
│   │       └── env.hcl                        # Production environment config
│   └── _envcommon/
│       └── vpc.hcl                            # Shared VPC configuration
├── terraform/
│   └── modules/
│       └── vpc/
│           ├── main.tf                        # VPC module implementation
│           ├── variables.tf                   # Module variables
│           └── outputs.tf                     # Module outputs
├── .gitea/
│   └── workflows/
│       └── atlantis-integration.yml           # Gitea Actions workflow
├── scripts/
│   └── setup-atlantis.sh                      # Automated setup script
├── docs/
│   └── ATLANTIS_GITOPS_GUIDE.md              # Complete workflow documentation
└── compliance/
    └── GITOPS_EVIDENCE_COLLECTION.md         # Evidence collection guide
```

## Key Features Implemented

### 1. **Atlantis GitOps Automation**
- Docker Compose deployment with all required services
- Gitea webhook integration for PR automation
- Multi-environment support (dev, staging, prod)
- Automated plan on PR creation
- Manual approval workflow for production

### 2. **Security Gates & Scanning**
- **Checkov**: Infrastructure security scanning
- **tfsec**: Terraform-specific security analysis
- **Terrascan**: Compliance policy scanning
- **OPA/Conftest**: Custom policy enforcement
- **Secrets scanning**: Trufflehog integration

### 3. **Terragrunt DRY Configuration**
- Hierarchical configuration structure
- Environment-specific settings
- Shared module configurations
- Remote state management with GCS
- Automatic backend generation

### 4. **CMMC 2.0 & NIST Compliance**
- Policy-as-code enforcement
- Complete audit trail
- Evidence collection automation
- SHA-256 hashing for integrity
- 365-day retention policies

### 5. **Cost Management**
- Infracost integration
- Cost estimates on every PR
- Threshold validation ($1000/month)
- Budget alerts and reporting

### 6. **Evidence Collection**
- Automated evidence generation
- GCS storage with versioning
- Compliance metadata tagging
- Hash verification
- Audit report generation

## Compliance Controls Implemented

### CMMC 2.0 Level 2
- **CM.L2-3.4.2**: Baseline configurations via Terragrunt
- **CM.L2-3.4.3**: Change tracking through Git and evidence collection
- **CM.L2-3.4.9**: Least functionality via network segmentation and IAM

### NIST SP 800-171
- **3.4.2**: Security baselines in code
- **3.4.3**: PR approval workflow
- **3.4.9**: Resource minimization policies

### NIST SP 800-53
- **CM-3**: Configuration change control via GitOps
- **CM-5**: Access restrictions through RBAC
- **CM-6**: Policy validation before deployment

## Workflow Process

### Developer Workflow

1. **Create Branch & Make Changes**
   ```bash
   git checkout -b feature/update-infrastructure
   # Edit terragrunt/environments/dev/vpc/terragrunt.hcl
   git commit -m "feat: update VPC configuration"
   git push origin feature/update-infrastructure
   ```

2. **Create Pull Request**
   - Atlantis automatically runs plan
   - Security scans execute
   - Cost estimate generated
   - Policy validation performed

3. **Review & Approve**
   - Security team reviews scan results
   - Cost approved if under threshold
   - Required approvals obtained

4. **Apply Changes**
   ```
   # In PR comment:
   atlantis apply
   ```

### Production Workflow

Production changes require:
- 2+ approvals
- All security gates passing
- Cost threshold validation
- Manual apply command
- Evidence collection

## Security Features

### Infrastructure Security
- Encryption at rest enforcement
- Private endpoints only
- Network segmentation
- Least privilege IAM
- VPC Service Controls for CUI data

### GitOps Security
- Webhook signature validation
- TLS/HTTPS for all endpoints
- Service account impersonation
- State file encryption
- Secrets scanning on every PR

### Compliance Security
- Default-deny firewall rules
- Mandatory audit logging
- Binary Authorization for GKE
- Backup requirements enforcement
- High availability for production

## Available Commands

### Setup & Configuration
```bash
make setup              # Complete setup
make setup-gcp          # Configure GCP resources
make generate-certs     # Generate TLS certificates
```

### Atlantis Operations
```bash
make start              # Start Atlantis
make stop               # Stop Atlantis
make restart            # Restart services
make logs               # View logs
make status             # Check status
```

### Validation & Testing
```bash
make validate           # Validate all configurations
make validate-env       # Validate specific environment
make fmt-check          # Check formatting
make fmt-fix            # Fix formatting
```

### Security Scanning
```bash
make security-scan      # Run all security scans
make checkov-scan       # Run Checkov
make tfsec-scan         # Run tfsec
make terrascan-scan     # Run Terrascan
make opa-validate       # Validate OPA policies
```

### Security & Infra Validation (App + Infra)
```bash
make security-suite     # Full app+infra suite with evidence
make security-infra     # Infra checks (IaC) + Nmap/testssl pen tests
make security-dast      # ZAP baseline + Nuclei + deploy validation
```

### DNS Management Shortcuts
```bash
make dns-backup         # Export Namecheap DNS (XML + YAML snapshot)
make dns-plan           # Diff desired vs live DNS -> evidence
make dns-apply-dry      # Dry-run Namecheap update (no write)
CONFIRM_OVERWRITE=1 make dns-apply   # Apply (replaces ALL hosts)
```

### Cost Management
```bash
make cost-estimate      # Generate cost estimate
make cost-diff          # Show cost difference
```

### Evidence & Compliance
```bash
make evidence-collect   # Collect evidence
make evidence-upload    # Upload to GCS
make evidence-list      # List recent evidence
make compliance-report  # Generate compliance report
```

### Backup & Restore
```bash
make backup             # Create backup
make backup-upload      # Upload backup to GCS
make restore            # Restore from backup
```

## GCP Resources Created

### Service Account
- Name: `atlantis-terraform@[project].iam.gserviceaccount.com`
- Roles: Compute Admin, Container Admin, Storage Admin, IAM Service Account User

### GCS Buckets
- State: `[project]-terraform-state`
- Evidence: `[project]-atlantis-evidence`
- Features: Versioning, retention policies, encryption

### Networking
- VPC with private subnets
- Cloud NAT for outbound access
- Firewall rules with default-deny
- Private Google Access enabled

## Evidence Storage Structure

```
gs://[project]-atlantis-evidence/
├── YYYY/MM/DD/
│   ├── pr-[number]/
│   │   ├── metadata.json
│   │   ├── plan/
│   │   ├── security/
│   │   ├── policy/
│   │   ├── cost/
│   │   └── hashes.sha256
│   └── daily-summary.json
└── backups/
```

## Monitoring & Alerting

### Metrics Tracked
- Infrastructure changes per environment
- Security scan pass/fail rates
- Policy violations
- Cost trends
- Approval times
- Evidence collection status

### Health Checks
```bash
make health-check       # Comprehensive health check
make metrics            # View Prometheus metrics
```

## Troubleshooting

### Common Issues

1. **Atlantis not responding**:
   ```bash
   make restart
   make logs
   ```

2. **State lock issues**:
   ```bash
   # In PR comment:
   atlantis unlock
   ```

3. **Policy failures**:
   - Review `/tmp/conftest-results.json`
   - Update configurations to meet policy requirements

4. **Cost threshold exceeded**:
   - Review Infracost report
   - Optimize resources or request exception

## Best Practices

1. **Branch Strategy**
   - Use feature branches for changes
   - Protect main/master branches
   - Require PR reviews

2. **Commit Standards**
   - Use conventional commits
   - Reference issue numbers
   - Include clear descriptions

3. **Security**
   - Never commit secrets
   - Use least privilege IAM
   - Enable MFA for production
   - Rotate credentials regularly

4. **Cost Management**
   - Review estimates before applying
   - Use preemptible instances for dev
   - Implement auto-shutdown policies
   - Regular optimization reviews

## Next Steps

1. **Configure Gitea Webhook**:
   - Go to Repository Settings → Webhooks
   - URL: `https://atlantis.gitea.local/events`
   - Events: Pull Request, Pull Request Comment

2. **Set Environment Variables**:
   ```bash
   cd atlantis
   cp .env.example .env
   # Edit with your values
   ```

3. **Test the Workflow**:
   - Create a test PR
   - Verify Atlantis responds
   - Check security scans
   - Review evidence collection

## Support & Documentation

- [Atlantis Documentation](https://www.runatlantis.io/)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
- [CMMC 2.0 Framework](https://www.acq.osd.mil/cmmc/)
- [NIST SP 800-171](https://csrc.nist.gov/publications/detail/sp/800-171/rev-2/final)

## Success Metrics

✅ **Completed Implementation**:
- Atlantis Docker Compose stack
- Terragrunt DRY configurations
- Security scanning integration
- OPA policy enforcement
- Cost estimation
- Evidence collection automation
- CMMC/NIST compliance mappings
- Complete documentation
- Makefile automation
- Production-ready workflows

---

*Implementation Date: 2024*
*Compliance: CMMC 2.0 Level 2, NIST SP 800-171*
*Version: 1.0.0*
