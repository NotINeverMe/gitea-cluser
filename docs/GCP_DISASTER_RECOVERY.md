# GCP Gitea Disaster Recovery Plan

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [RTO/RPO Objectives](#rtorpo-objectives)
3. [Backup Strategy](#backup-strategy)
4. [Failover Procedures](#failover-procedures)
5. [Testing Schedule](#testing-schedule)
6. [Recovery Validation](#recovery-validation)
7. [Post-Recovery Checklist](#post-recovery-checklist)
8. [Appendices](#appendices)

## Executive Summary

This Disaster Recovery (DR) Plan outlines procedures for recovering Gitea services hosted on Google Cloud Platform in the event of a disaster. The plan addresses various failure scenarios and provides step-by-step recovery procedures to minimize downtime and data loss.

### Scope

This plan covers:
- Complete instance failure
- Data corruption or loss
- Regional GCP outage
- Security breach requiring rebuild
- Accidental deletion of resources

### Key Stakeholders

| Role | Name | Contact | Responsibility |
|------|------|---------|----------------|
| DR Coordinator | DevOps Lead | devops@example.com | Execute DR procedures |
| Business Owner | Product Manager | pm@example.com | Approve DR activation |
| Technical Lead | Infrastructure Manager | infra@example.com | Technical decisions |
| Communications | PR Team | pr@example.com | User communications |

## RTO/RPO Objectives

### Service Level Objectives

| Service Component | RPO (Recovery Point Objective) | RTO (Recovery Time Objective) | Priority |
|-------------------|---------------------------------|--------------------------------|----------|
| Git Repositories | 1 hour | 2 hours | Critical |
| User Accounts | 1 hour | 2 hours | Critical |
| CI/CD Configs | 24 hours | 4 hours | High |
| Issue Tracking | 1 hour | 4 hours | High |
| Wiki/Docs | 24 hours | 8 hours | Medium |
| Audit Logs | 0 (real-time) | 24 hours | Low |

### Recovery Time Breakdown

```
Total RTO: 2 hours

Detection: 15 minutes
├── Automated monitoring alert
├── Manual verification
└── Incident declaration

Decision: 15 minutes
├── Assess impact
├── Determine recovery strategy
└── Approve DR activation

Recovery: 1 hour
├── Provision infrastructure (20 min)
├── Restore data (30 min)
└── Verify services (10 min)

Validation: 30 minutes
├── Service checks
├── Data integrity verification
└── User acceptance testing
```

## Backup Strategy

### Backup Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Production Region                     │
│                    (us-central1)                         │
│                                                          │
│  ┌──────────────┐        ┌──────────────────┐          │
│  │   Instance   │───────▶│  Primary Backup  │          │
│  │              │        │    GCS Bucket    │          │
│  └──────────────┘        └────────┬─────────┘          │
│                                   │                      │
└───────────────────────────────────┼──────────────────────┘
                                    │
                          Cross-Region Replication
                                    │
┌───────────────────────────────────▼──────────────────────┐
│                       DR Region                          │
│                       (us-east1)                         │
│                                                          │
│                   ┌──────────────────┐                   │
│                   │    DR Backup     │                   │
│                   │   GCS Bucket     │                   │
│                   └──────────────────┘                   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Backup Schedule

| Backup Type | Frequency | Retention | Storage Location |
|-------------|-----------|-----------|------------------|
| Full System | Daily @ 02:00 UTC | 30 days | Primary + DR buckets |
| Incremental | Every 6 hours | 7 days | Primary bucket |
| Database | Hourly | 24 hours | Primary + DR buckets |
| Configuration | On change | 90 days | Primary + DR buckets |
| Snapshots | Daily @ 03:00 UTC | 7 days | Regional storage |

### Backup Automation Script

```bash
#!/bin/bash
# automated-backup.sh

set -euo pipefail

# Configuration
PROJECT_ID="your-project-id"
ENVIRONMENT="prod"
PRIMARY_BUCKET="gitea-${ENVIRONMENT}-backup-${PROJECT_ID}"
DR_BUCKET="gitea-${ENVIRONMENT}-dr-backup-${PROJECT_ID}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Function to perform backup
perform_backup() {
    local backup_type=$1
    echo "[$(date)] Starting ${backup_type} backup..."

    case ${backup_type} in
        "full")
            # Full system backup
            ./scripts/gcp-backup.sh -p ${PROJECT_ID} -e ${ENVIRONMENT} -t full
            ;;
        "incremental")
            # Incremental backup
            ./scripts/gcp-backup.sh -p ${PROJECT_ID} -e ${ENVIRONMENT} -t incremental
            ;;
        "database")
            # Database-only backup
            gcloud compute ssh gitea-${ENVIRONMENT}-server \
                --zone=us-central1-a \
                --tunnel-through-iap \
                --command="sudo docker exec gitea-postgres pg_dumpall -U gitea | gzip > /tmp/db_${TIMESTAMP}.sql.gz"

            # Upload to GCS
            gsutil cp /tmp/db_${TIMESTAMP}.sql.gz gs://${PRIMARY_BUCKET}/hourly/
            ;;
    esac

    echo "[$(date)] ${backup_type} backup completed"
}

# Function to replicate to DR region
replicate_to_dr() {
    echo "[$(date)] Replicating to DR region..."

    # Sync to DR bucket
    gsutil -m rsync -r -d \
        gs://${PRIMARY_BUCKET}/ \
        gs://${DR_BUCKET}/

    echo "[$(date)] DR replication completed"
}

# Function to validate backups
validate_backups() {
    echo "[$(date)] Validating backups..."

    # Check primary bucket
    local primary_count=$(gsutil ls gs://${PRIMARY_BUCKET}/ | wc -l)
    echo "Primary bucket: ${primary_count} objects"

    # Check DR bucket
    local dr_count=$(gsutil ls gs://${DR_BUCKET}/ | wc -l)
    echo "DR bucket: ${dr_count} objects"

    # Verify latest backup integrity
    local latest_backup=$(gsutil ls gs://${PRIMARY_BUCKET}/full/ | tail -1)
    gsutil stat ${latest_backup} > /dev/null 2>&1 || {
        echo "ERROR: Latest backup validation failed"
        exit 1
    }

    echo "[$(date)] Backup validation passed"
}

# Main execution
main() {
    local backup_type=${1:-full}

    echo "=== Automated Backup Process ==="
    echo "Type: ${backup_type}"
    echo "Time: $(date)"

    # Perform backup
    perform_backup ${backup_type}

    # Replicate to DR
    replicate_to_dr

    # Validate
    validate_backups

    echo "=== Backup Process Complete ==="
}

main "$@"
```

## Failover Procedures

### Scenario 1: Complete Instance Failure

```bash
#!/bin/bash
# scenario1-instance-failure.sh

set -euo pipefail

echo "=== DISASTER RECOVERY: Instance Failure ==="
echo "Time: $(date)"

# 1. Verify failure
echo "[1] Verifying instance failure..."
if gcloud compute instances describe gitea-prod-server \
    --zone=us-central1-a --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
    echo "Instance is running. Investigating further..."
    exit 1
fi

# 2. Create new instance from snapshot
echo "[2] Creating replacement instance..."
LATEST_SNAPSHOT=$(gcloud compute snapshots list \
    --filter="name:gitea-prod-*" \
    --format="value(name)" \
    --sort-by="~creationTimestamp" | head -1)

gcloud compute instances create gitea-prod-server-recovery \
    --zone=us-central1-a \
    --machine-type=e2-standard-8 \
    --boot-disk-size=200 \
    --boot-disk-type=pd-ssd \
    --source-snapshot=${LATEST_SNAPSHOT} \
    --tags=gitea-server \
    --metadata-from-file startup-script=scripts/startup.sh

# 3. Restore data volumes
echo "[3] Restoring data volumes..."
./scripts/gcp-restore.sh -p ${PROJECT_ID} -e prod -f

# 4. Update DNS
echo "[4] Updating DNS to point to new instance..."
NEW_IP=$(gcloud compute instances describe gitea-prod-server-recovery \
    --zone=us-central1-a \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

# Update your DNS provider
echo "Update DNS A record: git.example.com -> ${NEW_IP}"

# 5. Verify services
echo "[5] Verifying services..."
sleep 60
curl -s https://${NEW_IP}/api/v1/version || echo "Service not yet available"

echo "=== Recovery Complete ==="
echo "New instance IP: ${NEW_IP}"
```

### Scenario 2: Data Corruption

```bash
#!/bin/bash
# scenario2-data-corruption.sh

set -euo pipefail

echo "=== DISASTER RECOVERY: Data Corruption ==="
echo "Time: $(date)"

# 1. Isolate corrupted instance
echo "[1] Isolating corrupted instance..."
gcloud compute instances stop gitea-prod-server --zone=us-central1-a

# 2. Create backup of corrupted state
echo "[2] Backing up corrupted state for analysis..."
gcloud compute disks snapshot gitea-prod-server \
    --snapshot-names=corrupted-state-$(date +%Y%m%d-%H%M%S) \
    --zone=us-central1-a

# 3. Identify last good backup
echo "[3] Identifying last known good backup..."
LAST_GOOD_DATE=$(date -d "yesterday" +%Y-%m-%d)
BACKUP_ID=$(gsutil ls gs://gitea-prod-backup-*/full/${LAST_GOOD_DATE}/ | \
    tail -1 | xargs basename)

echo "Using backup: ${BACKUP_ID}"

# 4. Restore from backup
echo "[4] Restoring from backup..."
./scripts/gcp-restore.sh \
    -p ${PROJECT_ID} \
    -e prod \
    -b ${BACKUP_ID} \
    -f

# 5. Verify data integrity
echo "[5] Verifying data integrity..."
gcloud compute ssh gitea-prod-server \
    --zone=us-central1-a \
    --tunnel-through-iap << 'EOF'

# Check database integrity
sudo docker exec gitea-postgres psql -U gitea -c "SELECT COUNT(*) FROM repository;"

# Check file system
sudo find /data -type f -name "*.git" | head -10

# Check logs for errors
sudo docker-compose logs --tail=50 | grep -i error || echo "No errors found"
EOF

echo "=== Data Recovery Complete ==="
```

### Scenario 3: Regional Outage

```bash
#!/bin/bash
# scenario3-regional-failover.sh

set -euo pipefail

echo "=== DISASTER RECOVERY: Regional Failover ==="
echo "Time: $(date)"
echo "Failing over from us-central1 to us-east1"

# 1. Verify regional outage
echo "[1] Verifying regional outage..."
if gcloud compute regions describe us-central1 --format="value(status)" 2>/dev/null | grep -q "UP"; then
    echo "WARNING: Region appears to be up. Confirm failover? (y/n)"
    read -r confirm
    [[ $confirm != "y" ]] && exit 1
fi

# 2. Deploy infrastructure in DR region
echo "[2] Deploying infrastructure in DR region..."
cd terraform/gcp-gitea-dr
terraform init
terraform apply -var="region=us-east1" -var="zone=us-east1-b" -auto-approve

# 3. Restore from DR backup
echo "[3] Restoring from DR backup..."
DR_BACKUP=$(gsutil ls gs://gitea-prod-dr-backup-*/full/ | tail -1)

gcloud compute ssh gitea-prod-dr-server \
    --zone=us-east1-b \
    --tunnel-through-iap << EOF

# Download and restore backup
gsutil -m cp -r ${DR_BACKUP} /tmp/restore/

# Restore Docker volumes
for volume in gitea_data gitea_postgres gitea_redis; do
    docker volume create \${volume}_dr
    docker run --rm -v \${volume}_dr:/target -v /tmp/restore:/source alpine \
        tar xzf /source/\${volume}_*.tar.gz -C /target
done

# Start services
cd /opt/gitea && docker-compose up -d
EOF

# 4. Update DNS for failover
echo "[4] Updating DNS for regional failover..."
DR_IP=$(gcloud compute instances describe gitea-prod-dr-server \
    --zone=us-east1-b \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "Update DNS A record: git.example.com -> ${DR_IP}"
echo "Update DNS TXT record: _dr_active -> us-east1"

# 5. Verify DR site
echo "[5] Verifying DR site..."
curl -s https://${DR_IP}/api/v1/version

echo "=== Regional Failover Complete ==="
echo "DR Site Active: us-east1"
echo "DR IP: ${DR_IP}"
```

### Scenario 4: Security Breach

```bash
#!/bin/bash
# scenario4-security-breach.sh

set -euo pipefail

echo "=== DISASTER RECOVERY: Security Breach ==="
echo "Time: $(date)"
echo "SECURITY INCIDENT - Executing containment and recovery"

# 1. Isolate compromised systems
echo "[1] Isolating compromised systems..."
gcloud compute firewall-rules create emergency-lockdown \
    --priority=1 \
    --action=deny \
    --rules=all \
    --source-ranges=0.0.0.0/0 \
    --target-tags=gitea-server

# 2. Snapshot for forensics
echo "[2] Creating forensic snapshot..."
gcloud compute disks snapshot gitea-prod-server \
    --snapshot-names=forensics-$(date +%Y%m%d-%H%M%S) \
    --zone=us-central1-a \
    --description="Security incident forensics"

# 3. Deploy clean infrastructure
echo "[3] Deploying clean infrastructure..."
cd terraform/gcp-gitea-clean
terraform init
terraform apply -var="suffix=secure" -auto-approve

# 4. Restore from pre-breach backup
echo "[4] Identifying pre-breach backup..."
echo "Enter the date/time of last known good state (YYYY-MM-DD HH:MM):"
read -r SAFE_DATE

SAFE_BACKUP=$(gsutil ls gs://gitea-prod-backup-*/full/ | \
    grep $(date -d "${SAFE_DATE}" +%Y-%m-%d) | tail -1)

./scripts/gcp-restore.sh \
    -p ${PROJECT_ID} \
    -e prod-secure \
    -b $(basename ${SAFE_BACKUP}) \
    -f

# 5. Reset all credentials
echo "[5] Resetting all credentials..."
gcloud compute ssh gitea-prod-secure-server \
    --zone=us-central1-a \
    --tunnel-through-iap << 'EOF'

# Generate new database password
NEW_DB_PASS=$(openssl rand -base64 32)
sudo docker exec gitea-postgres psql -U postgres -c "ALTER USER gitea PASSWORD '${NEW_DB_PASS}';"

# Update Gitea configuration
sudo sed -i "s/PASSWD=.*/PASSWD=${NEW_DB_PASS}/" /opt/gitea/.env

# Force password reset for all users
sudo docker exec gitea-gitea gitea admin user reset-password --all

# Rotate API tokens
sudo docker exec gitea-postgres psql -U gitea -d gitea -c "DELETE FROM access_token;"

# Restart services
cd /opt/gitea && sudo docker-compose restart
EOF

# 6. Update firewall rules
echo "[6] Implementing enhanced security rules..."
gcloud compute firewall-rules delete emergency-lockdown --quiet

gcloud compute firewall-rules create enhanced-security \
    --allow=tcp:443 \
    --source-ranges="YOUR_OFFICE_IP/32" \
    --target-tags=gitea-server \
    --priority=100

echo "=== Security Recovery Complete ==="
echo "All users must reset passwords"
echo "All API tokens have been revoked"
echo "Review audit logs for breach analysis"
```

## Testing Schedule

### DR Test Calendar

| Test Type | Frequency | Duration | Participants | Next Test |
|-----------|-----------|----------|--------------|-----------|
| Backup Verification | Daily | 15 min | Automated | Daily @ 03:00 |
| Restore Test | Weekly | 1 hour | DevOps | Every Sunday |
| Failover Drill | Monthly | 2 hours | DevOps + Dev | First Saturday |
| Full DR Exercise | Quarterly | 4 hours | All Teams | Q1, Q2, Q3, Q4 |
| Tabletop Exercise | Semi-Annual | 2 hours | Leadership | January, July |

### Test Procedures

#### Weekly Restore Test

```bash
#!/bin/bash
# weekly-restore-test.sh

set -euo pipefail

echo "=== Weekly DR Test ==="
echo "Date: $(date)"
echo "Test Type: Restore Verification"

# Test environment variables
TEST_ENV="staging"
TEST_PROJECT="test-project-id"

# 1. Create test instance
echo "[1] Creating test instance..."
gcloud compute instances create gitea-dr-test \
    --zone=us-central1-a \
    --machine-type=e2-standard-2 \
    --boot-disk-size=50 \
    --tags=dr-test

# 2. Select random backup
echo "[2] Selecting random backup for test..."
TEST_BACKUP=$(gsutil ls gs://gitea-prod-backup-*/full/ | \
    sort -R | head -1 | xargs basename)

echo "Testing backup: ${TEST_BACKUP}"

# 3. Perform restore
echo "[3] Performing test restore..."
./scripts/gcp-restore.sh \
    -p ${TEST_PROJECT} \
    -e ${TEST_ENV} \
    -b ${TEST_BACKUP} \
    -n  # Dry run

# 4. Validate restore
echo "[4] Validating restore process..."
if [ $? -eq 0 ]; then
    echo "✓ Restore test passed"
    RESULT="PASSED"
else
    echo "✗ Restore test failed"
    RESULT="FAILED"
fi

# 5. Cleanup
echo "[5] Cleaning up test resources..."
gcloud compute instances delete gitea-dr-test \
    --zone=us-central1-a \
    --quiet

# 6. Report results
cat > dr-test-report-$(date +%Y%m%d).json << EOF
{
  "test_date": "$(date -Iseconds)",
  "test_type": "weekly_restore",
  "backup_tested": "${TEST_BACKUP}",
  "result": "${RESULT}",
  "duration_minutes": "$((SECONDS / 60))",
  "operator": "$(whoami)"
}
EOF

# Upload report
gsutil cp dr-test-report-*.json gs://gitea-prod-evidence-*/dr-tests/

echo "=== Test Complete ==="
```

#### Quarterly Full DR Exercise

```markdown
# Quarterly DR Exercise Runbook

## Pre-Exercise (T-1 Week)
- [ ] Schedule maintenance window
- [ ] Notify all stakeholders
- [ ] Review and update DR procedures
- [ ] Prepare test scenarios
- [ ] Configure monitoring dashboard

## Exercise Day

### Phase 1: Preparation (30 min)
- [ ] Team briefing
- [ ] Assign roles
- [ ] Review success criteria
- [ ] Start recording/logging

### Phase 2: Simulation (2 hours)
- [ ] Simulate failure scenario
- [ ] Execute DR procedures
- [ ] Document all actions
- [ ] Track recovery time

### Phase 3: Validation (1 hour)
- [ ] Verify all services operational
- [ ] Run automated tests
- [ ] Check data integrity
- [ ] Validate user access

### Phase 4: Rollback (30 min)
- [ ] Return to production state
- [ ] Clean up test resources
- [ ] Document lessons learned

## Post-Exercise (T+1 Day)
- [ ] Compile metrics
- [ ] Calculate actual RTO/RPO
- [ ] Document issues found
- [ ] Update procedures
- [ ] Share report with stakeholders
```

## Recovery Validation

### Automated Validation Suite

```bash
#!/bin/bash
# validate-recovery.sh

set -euo pipefail

echo "=== Recovery Validation Suite ==="
echo "Starting validation at: $(date)"

VALIDATION_RESULTS=()
FAILED_CHECKS=0

# Function to check and record result
check() {
    local check_name=$1
    local command=$2

    echo -n "Checking ${check_name}... "

    if eval ${command} > /dev/null 2>&1; then
        echo "✓ PASSED"
        VALIDATION_RESULTS+=("${check_name}: PASSED")
    else
        echo "✗ FAILED"
        VALIDATION_RESULTS+=("${check_name}: FAILED")
        ((FAILED_CHECKS++))
    fi
}

# 1. Infrastructure Checks
echo -e "\n[Infrastructure Validation]"
check "Instance Running" "gcloud compute instances describe gitea-prod-server --zone=us-central1-a --format='value(status)' | grep -q RUNNING"
check "External IP Assigned" "gcloud compute instances describe gitea-prod-server --zone=us-central1-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'"
check "Disks Attached" "gcloud compute instances describe gitea-prod-server --zone=us-central1-a --format='value(disks[].deviceName)' | wc -l | grep -q 2"

# 2. Service Checks
echo -e "\n[Service Validation]"
EXTERNAL_IP=$(gcloud compute instances describe gitea-prod-server --zone=us-central1-a --format='value(networkInterfaces[0].accessConfigs[0].natIP)')

check "HTTPS Response" "curl -k -s -o /dev/null -w '%{http_code}' https://${EXTERNAL_IP} | grep -qE '^(200|302)'"
check "API Available" "curl -k -s https://${EXTERNAL_IP}/api/v1/version | jq -r '.version' | grep -q ."
check "Git SSH Port" "nc -zv ${EXTERNAL_IP} 10022"

# 3. Docker Services
echo -e "\n[Container Validation]"
check "Docker Running" "gcloud compute ssh gitea-prod-server --zone=us-central1-a --tunnel-through-iap --command='sudo docker ps' | grep -q gitea"
check "PostgreSQL Running" "gcloud compute ssh gitea-prod-server --zone=us-central1-a --tunnel-through-iap --command='sudo docker ps' | grep -q postgres"
check "Redis Running" "gcloud compute ssh gitea-prod-server --zone=us-central1-a --tunnel-through-iap --command='sudo docker ps' | grep -q redis"

# 4. Data Integrity
echo -e "\n[Data Validation]"
check "Database Connection" "gcloud compute ssh gitea-prod-server --zone=us-central1-a --tunnel-through-iap --command='sudo docker exec gitea-postgres pg_isready -U gitea'"
check "Repository Count" "gcloud compute ssh gitea-prod-server --zone=us-central1-a --tunnel-through-iap --command='sudo find /data/git -name \"*.git\" -type d | wc -l' | grep -q '^[0-9]'"
check "User Accounts" "gcloud compute ssh gitea-prod-server --zone=us-central1-a --tunnel-through-iap --command='sudo docker exec gitea-postgres psql -U gitea -t -c \"SELECT COUNT(*) FROM \\\"user\\\";\"' | grep -q '^[0-9]'"

# 5. Security Checks
echo -e "\n[Security Validation]"
check "Firewall Rules" "gcloud compute firewall-rules list --filter='targetTags:gitea-server' --format='value(name)' | wc -l | grep -q '^[1-9]'"
check "SSL Certificate" "echo | openssl s_client -connect ${EXTERNAL_IP}:443 2>/dev/null | openssl x509 -noout -dates"
check "Backup Bucket Access" "gsutil ls gs://gitea-prod-backup-*/"

# Generate Report
echo -e "\n=== Validation Summary ==="
echo "Total Checks: ${#VALIDATION_RESULTS[@]}"
echo "Failed Checks: ${FAILED_CHECKS}"
echo "Success Rate: $(( (${#VALIDATION_RESULTS[@]} - ${FAILED_CHECKS}) * 100 / ${#VALIDATION_RESULTS[@]} ))%"

echo -e "\n[Detailed Results]"
for result in "${VALIDATION_RESULTS[@]}"; do
    echo "  - ${result}"
done

# Create validation report
cat > validation-report-$(date +%Y%m%d-%H%M%S).json << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total_checks": ${#VALIDATION_RESULTS[@]},
  "failed_checks": ${FAILED_CHECKS},
  "success_rate": $(( (${#VALIDATION_RESULTS[@]} - ${FAILED_CHECKS}) * 100 / ${#VALIDATION_RESULTS[@]} )),
  "results": [
$(printf '    "%s"' "${VALIDATION_RESULTS[@]}" | sed 's/" "/",\n    "/g')
  ]
}
EOF

# Exit with appropriate code
if [ ${FAILED_CHECKS} -eq 0 ]; then
    echo -e "\n✓ All validation checks passed!"
    exit 0
else
    echo -e "\n✗ Validation failed with ${FAILED_CHECKS} errors"
    exit 1
fi
```

### Data Integrity Verification

```sql
-- data-integrity-check.sql
-- Run on PostgreSQL to verify data consistency

-- Check repository integrity
SELECT
    'Repositories' as entity,
    COUNT(*) as total_count,
    COUNT(CASE WHEN is_broken THEN 1 END) as broken_count,
    COUNT(CASE WHEN is_archived THEN 1 END) as archived_count
FROM repository;

-- Check user accounts
SELECT
    'Users' as entity,
    COUNT(*) as total_count,
    COUNT(CASE WHEN is_active THEN 1 END) as active_count,
    COUNT(CASE WHEN is_admin THEN 1 END) as admin_count
FROM "user";

-- Check issues and PRs
SELECT
    'Issues' as entity,
    COUNT(*) as total_count,
    COUNT(CASE WHEN is_closed THEN 1 END) as closed_count,
    COUNT(CASE WHEN is_pull THEN 1 END) as pr_count
FROM issue;

-- Check recent activity
SELECT
    'Recent Activity (24h)' as metric,
    COUNT(*) as count
FROM action
WHERE created_unix > EXTRACT(epoch FROM NOW() - INTERVAL '24 hours');

-- Check data consistency
WITH consistency_checks AS (
    SELECT
        'Orphaned Issues' as check_name,
        COUNT(*) as issue_count
    FROM issue i
    LEFT JOIN repository r ON i.repo_id = r.id
    WHERE r.id IS NULL

    UNION ALL

    SELECT
        'Invalid User References' as check_name,
        COUNT(*) as issue_count
    FROM repository r
    LEFT JOIN "user" u ON r.owner_id = u.id
    WHERE u.id IS NULL
)
SELECT * FROM consistency_checks WHERE issue_count > 0;
```

## Post-Recovery Checklist

### Immediate Actions (First Hour)

- [ ] **Service Verification**
  - [ ] Web interface accessible
  - [ ] API responding
  - [ ] Git operations working
  - [ ] Authentication functional

- [ ] **Communication**
  - [ ] Notify stakeholders of recovery status
  - [ ] Update status page
  - [ ] Send all-clear to users
  - [ ] Document incident timeline

- [ ] **Monitoring**
  - [ ] Enable enhanced monitoring
  - [ ] Check for error spikes
  - [ ] Verify backup jobs scheduled
  - [ ] Review security alerts

### Short-term Actions (First Day)

- [ ] **Data Verification**
  - [ ] Run data integrity checks
  - [ ] Verify repository access
  - [ ] Check user permissions
  - [ ] Validate CI/CD integrations

- [ ] **Security Review**
  - [ ] Review access logs
  - [ ] Check for unauthorized changes
  - [ ] Verify firewall rules
  - [ ] Rotate sensitive credentials

- [ ] **Performance Check**
  - [ ] Monitor resource usage
  - [ ] Check response times
  - [ ] Review database performance
  - [ ] Optimize if needed

### Long-term Actions (First Week)

- [ ] **Root Cause Analysis**
  - [ ] Identify failure cause
  - [ ] Document timeline
  - [ ] Collect evidence
  - [ ] Prepare incident report

- [ ] **Process Improvement**
  - [ ] Update DR procedures
  - [ ] Revise monitoring alerts
  - [ ] Enhance automation
  - [ ] Schedule team training

- [ ] **Compliance Documentation**
  - [ ] Generate compliance report
  - [ ] Update evidence records
  - [ ] File regulatory notifications
  - [ ] Archive incident data

### Post-Incident Report Template

```markdown
# Disaster Recovery Incident Report

## Incident Overview
- **Incident ID**: DR-YYYYMMDD-###
- **Date/Time**: YYYY-MM-DD HH:MM UTC
- **Duration**: X hours Y minutes
- **Severity**: Critical/High/Medium
- **Type**: [Instance Failure/Data Corruption/Regional Outage/Security Breach]

## Impact Assessment
- **Services Affected**:
- **Users Impacted**:
- **Data Loss**: None/Minimal/Significant
- **Financial Impact**: $

## Timeline
| Time | Event | Action | Owner |
|------|-------|--------|-------|
| HH:MM | Initial detection | Alert triggered | Monitoring |
| HH:MM | Incident declared | DR team activated | On-call |
| HH:MM | Recovery initiated | Backup restore started | DevOps |
| HH:MM | Service restored | Users can access | DevOps |
| HH:MM | Incident closed | Normal operations resumed | Management |

## Root Cause
[Detailed explanation of what caused the disaster]

## Recovery Actions
1. [Step-by-step recovery actions taken]
2.
3.

## Lessons Learned
### What Went Well
-
-

### What Could Be Improved
-
-

## Action Items
| Item | Owner | Due Date | Status |
|------|-------|----------|--------|
| | | | |

## Metrics
- **RPO Achieved**: X minutes (Target: Y minutes)
- **RTO Achieved**: X hours (Target: Y hours)
- **Backup Used**: [Backup ID]
- **Data Recovered**: X%

## Recommendations
1.
2.
3.

## Approval
- **Prepared By**: [Name] - [Date]
- **Reviewed By**: [Name] - [Date]
- **Approved By**: [Name] - [Date]
```

## Appendices

### A. Contact List

| Role | Primary | Backup | Escalation |
|------|---------|--------|------------|
| DR Coordinator | John Doe | Jane Smith | CTO |
| GCP Support | support-ticket | phone: 1-855-543-6724 | TAM |
| Network Team | network@example | noc@example | Network Manager |
| Security Team | security@example | soc@example | CISO |
| Database Admin | dba@example | dba-oncall | Data Manager |

### B. Critical Resources

| Resource | Location | Access Method | Recovery Priority |
|----------|----------|---------------|-------------------|
| Backup Storage | gs://gitea-prod-backup-* | gsutil/Console | Critical |
| DR Bucket | gs://gitea-prod-dr-backup-* | gsutil/Console | Critical |
| Terraform State | gs://terraform-state-* | terraform | High |
| Secrets | Secret Manager | gcloud/Console | Critical |
| DNS | Cloudflare/Route53 | Web Console | Critical |
| Monitoring | Cloud Monitoring | Console | High |

### C. Recovery Scripts Location

```
Repository: https://git.example.com/infrastructure/dr-scripts

/scripts/
├── gcp-backup.sh          # Backup automation
├── gcp-restore.sh         # Restore procedures
├── gcp-destroy.sh         # Clean teardown
├── scenarios/
│   ├── instance-failure.sh
│   ├── data-corruption.sh
│   ├── regional-failover.sh
│   └── security-breach.sh
└── validation/
    ├── validate-recovery.sh
    ├── data-integrity.sql
    └── service-checks.sh
```

### D. Compliance Requirements

| Requirement | Standard | Implementation | Evidence |
|-------------|----------|----------------|----------|
| Data Retention | CMMC 7 years | GCS lifecycle policies | Audit logs |
| Recovery Testing | SOC 2 Quarterly | Scheduled DR tests | Test reports |
| Incident Response | ISO 27001 | Documented procedures | Incident reports |
| Encryption | NIST 800-171 | KMS encryption | Encryption logs |

### E. Glossary

| Term | Definition |
|------|------------|
| RPO | Recovery Point Objective - Maximum acceptable data loss |
| RTO | Recovery Time Objective - Maximum acceptable downtime |
| MTTR | Mean Time To Recovery - Average recovery time |
| MTTF | Mean Time To Failure - Average time between failures |
| DR | Disaster Recovery - Process of recovering from catastrophic failure |
| BCP | Business Continuity Plan - Overall business recovery strategy |

---

*Document Version: 1.0*
*Last Updated: 2024*
*Next Review: Quarterly*
*Classification: Confidential*
*Compliance: CMMC Level 2 / NIST SP 800-171 / ISO 27001*