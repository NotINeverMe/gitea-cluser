# SSDF Evidence Collection - Quick Start Guide

Get up and running with SSDF evidence collection in 15 minutes.

## Prerequisites

- Python 3.11 or higher
- PostgreSQL 14 or higher
- Google Cloud account with Storage access
- Gitea instance with Actions enabled
- (Optional) SonarQube, Trivy, Syft, Cosign

## Step 1: Clone and Setup

```bash
cd /home/notme/Desktop/gitea/ssdf/evidence

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

## Step 2: Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

**Minimum required settings:**

```bash
GITEA_URL=http://localhost:3000
GITEA_TOKEN=your-gitea-token
GCP_PROJECT=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
POSTGRES_HOST=localhost
POSTGRES_PASSWORD=your-db-password
```

## Step 3: Setup GCS Bucket

```bash
# Make script executable
chmod +x config/setup-gcs-bucket.sh

# Run setup (interactive)
./config/setup-gcs-bucket.sh

# Or with environment variables
export GCP_PROJECT=your-project-id
export GCS_EVIDENCE_BUCKET=compliance-evidence-ssdf
./config/setup-gcs-bucket.sh
```

This will:
- Create GCS bucket with 7-year retention
- Enable versioning and logging
- Apply lifecycle policy
- Create service account
- Set permissions

## Step 4: Initialize Database

```bash
# Create database and tables
psql -U postgres -f schemas/evidence-registry.sql

# Verify tables were created
psql -U postgres -d compliance -c "\dt"
```

**Expected output:**

```
                   List of relations
 Schema |            Name             | Type  |  Owner
--------+-----------------------------+-------+----------
 public | evidence_registry           | table | postgres
 public | practice_coverage           | table | postgres
 public | ssdf_practices_reference    | table | postgres
 public | tools_inventory             | table | postgres
```

## Step 5: Test Configuration

```bash
# Test database connection
python3 -c "
import psycopg2
conn = psycopg2.connect(
    host='localhost',
    database='compliance',
    user='evidence_collector',
    password='your-password'
)
print('Database: OK')
conn.close()
"

# Test GCS access
gsutil ls gs://compliance-evidence-ssdf/
# Expected: empty bucket or list of contents

# Test Gitea API
curl -H "Authorization: token $GITEA_TOKEN" \
     http://localhost:3000/api/v1/user
# Expected: JSON with user info
```

## Step 6: Collect Your First Evidence

```bash
# Example: Collect evidence from a build
python ssdf-evidence-collector.py \
  --repository owner/repo-name \
  --workflow-id 12345 \
  --run-number 1 \
  --commit-sha abc123def456 \
  --sonar-project my-project-key
```

**What happens:**

1. Connects to Gitea API
2. Downloads workflow artifacts
3. Fetches SonarQube scan results
4. Collects Trivy scan reports
5. Gathers SBOM files
6. Packages everything with SHA-256 manifest
7. Uploads to GCS
8. Registers in PostgreSQL

**Expected output:**

```
Evidence Collection Complete
GCS URI: gs://compliance-evidence-ssdf/repo/2025/10/build-uuid/evidence.tar.gz
Build ID: 550e8400-e29b-41d4-a716-446655440000
Practices Covered: 15/42
Coverage: 35.7%
```

## Step 7: Verify Evidence

```bash
# Verify the evidence package
python verify-evidence.py \
  --gcs-uri gs://compliance-evidence-ssdf/repo/2025/10/build-uuid/evidence.tar.gz \
  --report verification-report.txt

# Check the report
cat verification-report.txt
```

**Expected checks:**

- ✓ GCS Download
- ✓ Package Extraction
- ✓ Manifest Integrity
- ✓ File Hash Verification
- ✓ SSDF Coverage
- ✓ Signature Verification (if cosign enabled)

## Step 8: Query Evidence

```bash
# Query by repository
python query-evidence.py --repo owner/repo-name

# Query by date range
python query-evidence.py \
  --start 2025-01-01 \
  --end 2025-12-31

# Query by SSDF practice
python query-evidence.py --practice PW.9.1

# Generate compliance report
python query-evidence.py \
  --report \
  --format markdown \
  --output compliance-report.md
```

## Common Issues & Solutions

### Issue: "Database connection failed"

**Solution:**

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Verify password
psql -U evidence_collector -d compliance -W

# Check pg_hba.conf allows connections
sudo nano /etc/postgresql/14/main/pg_hba.conf
# Add: host compliance evidence_collector 127.0.0.1/32 md5
sudo systemctl restart postgresql
```

### Issue: "GCS permission denied"

**Solution:**

```bash
# Authenticate
gcloud auth application-default login

# Or use service account
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json

# Verify access
gsutil ls gs://compliance-evidence-ssdf/
```

### Issue: "Gitea API 401 Unauthorized"

**Solution:**

```bash
# Create new access token in Gitea
# Settings → Applications → Generate New Token
# Required scopes: repo, workflow, read:org

# Test token
curl -H "Authorization: token YOUR_TOKEN" \
     http://localhost:3000/api/v1/user
```

### Issue: "Low SSDF coverage"

This is normal for first runs. Coverage increases as you:

1. Enable more tools (SonarQube, Trivy, etc.)
2. Integrate SBOM generation
3. Add attestation signing
4. Implement more practices

**To improve coverage:**

```bash
# Check which practices are missing
python query-evidence.py --repo your-repo

# Enable more tools in config
nano config/collector-config.json
# Set "enabled": true for all tools
```

## Integration with CI/CD

### Gitea Actions

Add to `.gitea/workflows/evidence-collection.yml`:

```yaml
name: Collect Evidence

on:
  push:
    branches: [main]

jobs:
  evidence:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run security scans
        run: |
          # Your existing scan steps
          trivy image --format json --output trivy.json myapp:latest
          syft myapp:latest -o spdx-json > sbom.spdx.json

      - name: Collect evidence
        env:
          GITEA_TOKEN: ${{ secrets.GITEA_TOKEN }}
          GCP_PROJECT: ${{ secrets.GCP_PROJECT }}
          GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_CREDS }}
        run: |
          pip install -r requirements.txt
          python ssdf-evidence-collector.py \
            --repository ${{ github.repository }} \
            --workflow-id ${{ github.run_id }} \
            --run-number ${{ github.run_number }} \
            --commit-sha ${{ github.sha }}
```

## Next Steps

1. **Increase Coverage**: Enable more security tools
2. **Add Signing**: Implement Cosign for attestations
3. **Automate Collection**: Trigger on every build
4. **Setup Monitoring**: Create dashboards for coverage trends
5. **Compliance Reports**: Generate monthly reports

## Reference Commands

```bash
# Collector
python ssdf-evidence-collector.py --help

# Manifest
python manifest-generator.py verify <build-id>
python manifest-generator.py summary <build-id>

# Verification
python verify-evidence.py --gcs-uri <uri> --report report.txt

# Query
python query-evidence.py --repo <repo>
python query-evidence.py --practice PW.9.1
python query-evidence.py --report --format markdown

# Database
psql -U evidence_query -d compliance

# GCS
gsutil ls gs://compliance-evidence-ssdf/
gsutil lifecycle get gs://compliance-evidence-ssdf/
```

## Support

- **Documentation**: See `README.md` for full details
- **Schemas**: Check `schemas/` for database structure
- **Config**: Review `config/collector-config.json`
- **Logs**: Check `/var/log/evidence-collector.log`

## Security Notes

1. **Never commit secrets**: Use `.env` (in .gitignore)
2. **Rotate tokens**: Regular rotation of API tokens
3. **Limit access**: Use IAM with least privilege
4. **Enable audit**: Keep GCS access logs
5. **Sign evidence**: Always use Cosign when possible

## Monitoring

```bash
# Check recent collections
python query-evidence.py --repo your-repo | head -20

# Coverage statistics
psql -U evidence_query -d compliance \
  -c "SELECT * FROM compliance_summary;"

# Practice frequency
psql -U evidence_query -d compliance \
  -c "SELECT * FROM practice_frequency LIMIT 10;"

# Storage usage
gsutil du -sh gs://compliance-evidence-ssdf/
```

## Maintenance

```bash
# Backup database
pg_dump -U postgres compliance > backup.sql

# Clean old temp files
find /tmp/evidence-* -type d -mtime +7 -exec rm -rf {} +

# Check GCS lifecycle
gsutil lifecycle get gs://compliance-evidence-ssdf/

# Verify retention
python query-evidence.py --start 2018-01-01 --end 2018-12-31
# Should be empty (7+ years old, deleted by lifecycle)
```

---

**You're now ready to collect SSDF compliance evidence!**

For detailed documentation, see `README.md`.
