# DNS Update Guide for Gitea GCP Deployment

## Overview

This guide covers updating DNS records for the Gitea GCP deployment using the `gcp-dns-update.sh` script with Namecheap API integration.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Script Features](#script-features)
- [Usage Examples](#usage-examples)
- [Parameters Reference](#parameters-reference)
- [Security & Credentials](#security--credentials)
- [Modes of Operation](#modes-of-operation)
- [Evidence & Compliance](#evidence--compliance)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Prerequisites

### Required

1. **GCP Project** with access to Secret Manager
2. **Namecheap API Access** enabled on your account
3. **gcloud CLI** installed and authenticated
4. **Namecheap API Credentials** stored in GCP Secret Manager:
   - `namecheap-api-user`
   - `namecheap-api-key`
   - `namecheap-api-ip`

### Creating Secrets

Use the `scripts/create-secrets.sh` script to create Namecheap credentials:

```bash
cd scripts
./create-secrets.sh -p cui-gitea-prod -r us-central1

# You'll be prompted to enter:
# - Namecheap API User
# - Namecheap API Key
# - Namecheap API Whitelisted IP
```

### Enabling Namecheap API

1. Log in to your Namecheap account
2. Navigate to **Profile** → **Tools** → **Namecheap API**
3. Enable API access
4. Whitelist your IP address (or use Cloud NAT IP for GCP)
5. Note your API credentials

## Quick Start

### Update Gitea A Record

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142
```

### Dry-Run (Preview Changes)

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142 \
  -n
```

### Update with Custom TTL

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142 \
  -l 600
```

## Script Features

### Safe Read-Modify-Write Workflow

The script uses a safe approach that preserves existing DNS records:

1. **Fetch** current DNS records via Namecheap getHosts API
2. **Parse** existing records into structured format
3. **Update** the target record while preserving others
4. **Apply** complete record set via setHosts API
5. **Verify** changes were applied correctly
6. **Generate** compliance evidence

### GCP Secret Manager Integration

Automatically retrieves Namecheap API credentials from GCP Secret Manager:

- No credentials in shell history
- Centralized secret management
- Audit trail for secret access
- IAM-based access control

### Compliance Evidence

Generates comprehensive evidence for CMMC/NIST compliance:

- **Before state**: DNS records before changes
- **After state**: DNS records after changes
- **Change manifest**: JSON with change metadata
- **API responses**: Raw XML responses from Namecheap

Evidence files are stored in: `terraform/gcp-gitea/evidence/`

## Usage Examples

### Basic A Record Update

Update the gitea subdomain to point to a new IP:

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142
```

### CNAME Record

Create or update a CNAME record:

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s dashboard \
  -t CNAME \
  -i lb.example.com
```

### Apex Domain (@)

Update the apex/root domain:

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s @ \
  -i 34.63.227.142
```

### Multiple Subdomains (Run Multiple Times)

For multiple subdomains, run the script once per subdomain:

```bash
# Update gitea
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142

# Update atlantis
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s atlantis -t CNAME -i lb.example.com

# Update dashboard
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s dashboard -t CNAME -i lb.example.com
```

### Using Manual Credentials

If you don't want to use Secret Manager:

```bash
./scripts/gcp-dns-update.sh \
  -s gitea \
  -i 34.63.227.142 \
  --api-user myusername \
  --api-key myapikey123456 \
  --api-ip 203.0.113.10
```

### Verbose Mode

Enable verbose output for debugging:

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142 \
  -v
```

## Parameters Reference

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-s SUBDOMAIN` | Subdomain to update | `gitea`, `dashboard`, `@` |
| `-i IP_ADDRESS` | Target IP or hostname | `34.63.227.142`, `lb.example.com` |

### Optional Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-p PROJECT_ID` | GCP project (required for Secret Manager) | - | `cui-gitea-prod` |
| `-d DOMAIN` | Base domain | `cui-secure.us` | `example.com` |
| `-t RECORD_TYPE` | Record type | `A` | `A`, `CNAME`, `TXT`, `MX` |
| `-l TTL` | Time to live (seconds) | `300` | `600`, `1800` |
| `-m MODE` | Operation mode | `update-single` | `update-single`, `replace-all` |
| `-n` | Dry-run mode (no changes) | `false` | `-n` |
| `-v` | Verbose output | `false` | `-v` |
| `-h` | Show help message | - | `-h` |

### Advanced Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--api-user USER` | Override API user | `--api-user myuser` |
| `--api-key KEY` | Override API key | `--api-key abc123...` |
| `--api-ip IP` | Override whitelisted IP | `--api-ip 203.0.113.10` |

## Security & Credentials

### Storing Credentials in Secret Manager

**Recommended approach** for production:

```bash
# Create secrets using the helper script
cd scripts
./create-secrets.sh -p cui-gitea-prod -r us-central1

# Or create manually
echo -n "my-api-user" | gcloud secrets create namecheap-api-user \
  --data-file=- \
  --project=cui-gitea-prod

echo -n "my-api-key" | gcloud secrets create namecheap-api-key \
  --data-file=- \
  --project=cui-gitea-prod

echo -n "203.0.113.10" | gcloud secrets create namecheap-api-ip \
  --data-file=- \
  --project=cui-gitea-prod
```

### Retrieving Credentials

View stored credentials (requires `secretmanager.secretAccessor` role):

```bash
gcloud secrets versions access latest \
  --secret=namecheap-api-user \
  --project=cui-gitea-prod
```

### IAM Permissions

Required IAM roles for script execution:

- **`roles/secretmanager.secretAccessor`** - To read API credentials
- **`roles/logging.logWriter`** - To write audit logs (optional)

Grant permissions:

```bash
gcloud projects add-iam-policy-binding cui-gitea-prod \
  --member="user:your-email@example.com" \
  --role="roles/secretmanager.secretAccessor"
```

## Modes of Operation

### Update-Single Mode (Default, Recommended)

Safely updates a single DNS record while preserving all others:

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142 \
  -m update-single
```

**Behavior:**
- Fetches all existing DNS records
- Updates only the specified subdomain
- Preserves all other records
- Safe for production use

**Use Cases:**
- Updating IP address for a service
- Adding new subdomains
- Changing record types

### Replace-All Mode (Dangerous!)

**⚠️ WARNING**: This mode **deletes all existing DNS records** and replaces them with only the specified record.

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142 \
  -m replace-all
```

**Behavior:**
- **REMOVES** all existing DNS records
- Creates only the specified record
- Requires explicit "YES" confirmation
- Not recommended for production

**Use Cases:**
- Starting fresh with DNS configuration
- Delegated subzone management
- Testing/development environments

## Evidence & Compliance

### Generated Evidence Files

Every DNS update generates compliance evidence:

| File | Description | Location |
|------|-------------|----------|
| `dns-update-TIMESTAMP.json` | Change manifest | `evidence/` |
| `dns-before-TIMESTAMP.xml` | Pre-change state | `evidence/` |
| `dns-after-TIMESTAMP.xml` | Post-change state | `evidence/` |

### Compliance Controls

**CMMC 2.0:**
- **CM.L2-3.4.2**: System Baseline Configuration
- **AU.L2-3.3.1**: Event Logging
- **IA.L2-3.5.7**: Credential Management

**NIST SP 800-171 Rev. 2:**
- **§3.4.2**: Baseline configuration management
- **§3.3.1**: System audit event logging
- **§3.5.7**: Authenticator management

### Evidence Manifest Example

```json
{
  "timestamp": "2025-10-08T15:30:00Z",
  "operation": "dns-update",
  "domain": "cui-secure.us",
  "subdomain": "gitea",
  "record_type": "A",
  "target": "34.63.227.142",
  "ttl": 300,
  "mode": "update-single",
  "dry_run": false,
  "gcp_project": "cui-gitea-prod",
  "compliance": {
    "cmmc_controls": ["CM.L2-3.4.2", "AU.L2-3.3.1", "IA.L2-3.5.7"],
    "nist_controls": ["CM-2", "AU-3", "IA-5"]
  },
  "evidence_files": {
    "before": "dns-before-20251008-153000.xml",
    "after": "dns-after-20251008-153000.xml"
  },
  "status": "success"
}
```

## Troubleshooting

### Error: "Secret not found"

**Problem**: Namecheap API credentials not in Secret Manager

**Solution**:
```bash
cd scripts
./create-secrets.sh -p cui-gitea-prod -r us-central1
```

### Error: "Namecheap API returned error"

**Problem**: API authentication failed or IP not whitelisted

**Solutions**:
1. Verify API credentials are correct
2. Check IP whitelist in Namecheap dashboard
3. Ensure API is enabled on your account
4. Check if you're using Cloud NAT IP (not local IP)

### Error: "gcloud CLI not found"

**Problem**: gcloud not installed or not in PATH

**Solution**:
```bash
# Install gcloud
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

### Records Not Updating

**Problem**: Changes applied but not visible

**Possible Causes**:
1. **DNS propagation delay** - Wait 5-15 minutes
2. **TTL caching** - Old TTL still in effect
3. **Wrong domain** - Verify SLD/TLD split
4. **API call failed** - Check evidence XML files

**Verification**:
```bash
# Check via DNS lookup
dig gitea.cui-secure.us +short

# Check via Namecheap API
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142 -n
```

### Permission Denied

**Problem**: Cannot access Secret Manager

**Solution**:
```bash
# Grant yourself access
gcloud projects add-iam-policy-binding cui-gitea-prod \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/secretmanager.secretAccessor"
```

## Best Practices

### 1. Always Use Dry-Run First

Preview changes before applying:

```bash
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142 -n
```

### 2. Use Update-Single Mode

Prefer `update-single` (default) over `replace-all`:

```bash
# Good: Preserves existing records
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142

# Dangerous: Deletes everything
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142 -m replace-all
```

### 3. Keep TTL Reasonable

Use appropriate TTL values:

- **Development**: 300 (5 minutes) - allows quick changes
- **Staging**: 600 (10 minutes) - balance flexibility/caching
- **Production**: 1800-3600 (30-60 minutes) - reduce DNS lookups

### 4. Store Credentials in Secret Manager

Never hardcode credentials:

```bash
# Good: Uses Secret Manager
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142

# Bad: Credentials in history
./scripts/gcp-dns-update.sh -s gitea -i 34.63.227.142 --api-key mykey123
```

### 5. Automate Post-Deployment

Integrate with terraform outputs:

```bash
# Get IP from terraform
EXTERNAL_IP=$(cd terraform/gcp-gitea && terraform output -raw instance_external_ip)

# Update DNS
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i "$EXTERNAL_IP"
```

### 6. Document Changes

Keep a change log:

```bash
# Create change record
echo "$(date): Updated gitea.cui-secure.us to 34.63.227.142" >> dns-changes.log

# Or use git
git add terraform/gcp-gitea/evidence/
git commit -m "DNS: Update gitea to 34.63.227.142"
```

### 7. Verify After Changes

Always verify DNS propagation:

```bash
# Update DNS
./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142

# Wait for propagation
sleep 60

# Verify
dig gitea.cui-secure.us +short
# Expected: 34.63.227.142
```

### 8. Use Verbose Mode for Debugging

Enable verbose output when troubleshooting:

```bash
./scripts/gcp-dns-update.sh \
  -p cui-gitea-prod \
  -s gitea \
  -i 34.63.227.142 \
  -v
```

## Integration Examples

### Makefile Target

Add to project Makefile:

```makefile
.PHONY: dns-update
dns-update: ## Update DNS record for Gitea
	@echo "Fetching external IP from Terraform..."
	@cd terraform/gcp-gitea && \
	EXTERNAL_IP=$$(terraform output -raw instance_external_ip) && \
	cd ../.. && \
	./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i $$EXTERNAL_IP

.PHONY: dns-update-dry
dns-update-dry: ## Preview DNS update
	@cd terraform/gcp-gitea && \
	EXTERNAL_IP=$$(terraform output -raw instance_external_ip) && \
	cd ../.. && \
	./scripts/gcp-dns-update.sh -p cui-gitea-prod -s gitea -i $$EXTERNAL_IP -n
```

Usage:
```bash
make dns-update-dry  # Preview
make dns-update      # Apply
```

### Post-Deployment Script

Add to `scripts/gcp-deploy.sh`:

```bash
# After successful deployment
log_info "Updating DNS records..."
if ./scripts/gcp-dns-update.sh -p "${PROJECT_ID}" -s gitea -i "${EXTERNAL_IP}"; then
    log_success "DNS updated successfully"
else
    log_warn "DNS update failed - update manually"
fi
```

### CI/CD Pipeline

GitHub Actions example:

```yaml
- name: Update DNS
  run: |
    EXTERNAL_IP=$(cd terraform/gcp-gitea && terraform output -raw instance_external_ip)
    ./scripts/gcp-dns-update.sh \
      -p cui-gitea-prod \
      -s gitea \
      -i "$EXTERNAL_IP"
  env:
    GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

## Related Documentation

- [Namecheap API Documentation](https://www.namecheap.com/support/api/intro/)
- [GCP Secret Manager](https://cloud.google.com/secret-manager/docs)
- [DNS_ACTION_PLAN_NAMECHEAP.md](DNS_ACTION_PLAN_NAMECHEAP.md) - Original DNS plan
- [GCP_DEPLOYMENT_GUIDE.md](GCP_DEPLOYMENT_GUIDE.md) - Full deployment guide

## Support

For issues:
1. Check this guide's [Troubleshooting](#troubleshooting) section
2. Review evidence files in `terraform/gcp-gitea/evidence/`
3. Enable verbose mode (`-v`) for detailed debugging
4. Contact platform team or DevSecOps lead

## Changelog

### 2025-10-08 - v1.0.0
- Initial release
- GCP Secret Manager integration
- Safe read-modify-write workflow
- Compliance evidence generation
- Dry-run support
- Comprehensive error handling
