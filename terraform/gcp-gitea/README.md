# Gitea GCP Terraform Deployment

## CMMC 2.0 Level 2 & NIST SP 800-171 Rev. 2 Compliant Infrastructure

This Terraform module deploys a production-ready, security-hardened Gitea instance on Google Cloud Platform with full CMMC 2.0 Level 2 and NIST SP 800-171 Rev. 2 compliance.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                ┌──────▼──────┐
                │ Cloud Armor │ WAF Protection
                │     WAF     │
                └──────┬──────┘
                       │
            ┌──────────▼──────────┐
            │   External IP       │
            │   Load Balancer     │
            └──────────┬──────────┘
                       │
         ┌─────────────▼─────────────┐
         │      VPC Network          │
         │   ┌─────────────────┐    │
         │   │  Subnet         │    │
         │   │  10.0.1.0/24    │    │
         │   └────────┬────────┘    │
         │            │              │
         │   ┌────────▼────────┐    │
         │   │ Compute Engine  │    │
         │   │   Instance      │    │
         │   │  ┌──────────┐  │    │
         │   │  │  Gitea   │  │    │
         │   │  │ PostgreSQL│  │    │
         │   │  │  Runner   │  │    │
         │   │  └──────────┘  │    │
         │   └─────────────────┘    │
         └───────────────────────────┘
                       │
         ┌─────────────▼─────────────┐
         │     Cloud Storage         │
         │  ┌──────┬──────┬──────┐  │
         │  │Evidence│Backup│ Logs │ │
         │  └──────┴──────┴──────┘  │
         └───────────────────────────┘
```

## Features

### Security & Compliance
- **CMMC 2.0 Level 2** compliant infrastructure
- **NIST SP 800-171 Rev. 2** security controls
- **CIS Level 2** hardened Ubuntu 22.04 LTS
- **Shielded VM** with Secure Boot, vTPM, and integrity monitoring
- **Cloud KMS** encryption for all data at rest
- **Secret Manager** for credential storage
- **Cloud Armor WAF** for DDoS and application protection
- **VPC Flow Logs** for network monitoring
- **OS Login** for centralized SSH key management
- **Identity-Aware Proxy** for secure administrative access

### High Availability & Reliability
- Automated daily backups with configurable retention
- Disk snapshots for point-in-time recovery
- Cross-region backup replication (optional)
- Health checks and uptime monitoring
- Auto-restart on failure
- Persistent data volumes

### Monitoring & Alerting
- Cloud Monitoring dashboards
- Custom alert policies for:
  - Instance availability
  - CPU/Memory/Disk usage
  - Security events
  - Uptime failures
- Cloud Logging integration
- Audit trail with 7-year retention

### DevSecOps Features
- Docker Compose stack with PostgreSQL
- Gitea Actions runner for CI/CD
- Evidence collection for compliance auditing
- Automated security updates
- Log rotation and management
- Backup automation with GCS integration

## Prerequisites

1. **GCP Project**: Active project with billing enabled
2. **APIs Enabled**:
   ```bash
   gcloud services enable compute.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable cloudkms.googleapis.com
   gcloud services enable secretmanager.googleapis.com
   gcloud services enable monitoring.googleapis.com
   gcloud services enable logging.googleapis.com
   ```
3. **Terraform**: Version 1.5.0 or higher
4. **gcloud CLI**: Authenticated with appropriate permissions

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd terraform/gcp-gitea
   ```

2. **Copy and configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Review the plan**:
   ```bash
   terraform plan
   ```

5. **Apply the configuration**:
   ```bash
   terraform apply
   ```

6. **Access Gitea**:
   - Get the external IP: `terraform output instance_external_ip`
   - Configure DNS to point your domain to this IP
   - Access: `https://your-domain.com`

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP Project ID | `my-gitea-project` |
| `gitea_domain` | Domain for Gitea | `git.example.com` |
| `gitea_admin_email` | Admin email address | `admin@example.com` |

### Important Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `prod` | Environment (dev/staging/prod) |
| `region` | `us-central1` | GCP region |
| `machine_type` | `e2-standard-8` | Instance type |
| `data_disk_size` | `500` | Data disk size in GB |
| `alert_email` | `""` | Email for alerts |
| `enable_cross_region_backup` | `false` | Enable DR backups |

## Security Controls Implemented

### NIST SP 800-171 Rev. 2 Controls

| Control | Description | Implementation |
|---------|-------------|----------------|
| AC.L2-3.1.1 | Authorized Access Control | IAM roles, service accounts |
| AC.L2-3.1.5 | Least Privilege | Minimal permissions |
| AU.L2-3.3.1 | Event Logging | Cloud Logging, auditd |
| AU.L2-3.3.4 | Audit Record Review | Evidence collection |
| IA.L2-3.5.1 | Identification & Authentication | OS Login, IAP |
| SC.L2-3.13.8 | Transmission Confidentiality | HTTPS only |
| SC.L2-3.13.11 | Cryptographic Protection | Cloud KMS |
| SI.L2-3.14.1 | System Monitoring | Cloud Monitoring |

## File Structure

```
terraform/gcp-gitea/
├── versions.tf          # Provider configuration
├── main.tf             # Main configuration and locals
├── variables.tf        # Input variables
├── network.tf          # VPC and networking resources
├── compute.tf          # Compute Engine instance
├── storage.tf          # Cloud Storage buckets
├── security.tf         # KMS, secrets, service accounts
├── monitoring.tf       # Monitoring and alerting
├── outputs.tf          # Output values
├── startup-script.sh   # VM initialization script
├── terraform.tfvars.example  # Example variables
├── evidence/           # Audit evidence (auto-generated)
└── README.md          # This file
```

## Operations

### SSH Access

```bash
# Via IAP (recommended)
gcloud compute ssh --zone=us-central1-a gitea-vm --project=PROJECT_ID --tunnel-through-iap

# Create SSH tunnel for local access
gcloud compute ssh --zone=us-central1-a gitea-vm --project=PROJECT_ID --tunnel-through-iap -- -L 8080:localhost:443 -N
```

### Backup Management

```bash
# Manual backup
ssh gitea-vm
sudo /usr/local/bin/gitea-backup.sh

# List backups in GCS
gsutil ls gs://BACKUP_BUCKET/

# Restore from backup
# 1. Stop Gitea
docker-compose -f /mnt/gitea-data/docker-compose.yml down

# 2. Restore data
gsutil cp gs://BACKUP_BUCKET/daily/backup.tar.gz /tmp/
tar -xzf /tmp/backup.tar.gz -C /mnt/gitea-data/

# 3. Start Gitea
docker-compose -f /mnt/gitea-data/docker-compose.yml up -d
```

### Monitoring

Access the monitoring dashboard:
```bash
terraform output dashboard_url
```

View logs:
```bash
gcloud logging read 'resource.type="gce_instance"' --project=PROJECT_ID --limit=50
```

### Secret Management

```bash
# List secrets
gcloud secrets list --project=PROJECT_ID

# Update admin password
gcloud secrets versions add admin-password --data-file=- --project=PROJECT_ID
```

## Disaster Recovery

1. **Automated Backups**: Daily backups at 2 AM UTC
2. **Snapshot Policy**: Daily disk snapshots with 30-day retention
3. **Cross-Region Replication**: Optional DR bucket in secondary region
4. **Recovery Time Objective (RTO)**: < 4 hours
5. **Recovery Point Objective (RPO)**: < 24 hours

## Cost Optimization

### Estimated Monthly Costs (USD)

| Resource | Cost |
|----------|------|
| Compute Engine (e2-standard-8) | ~$195 |
| Persistent Disk (700GB SSD) | ~$119 |
| Cloud Storage | ~$10 |
| Static IP | ~$7 |
| Cloud NAT | ~$45 |
| Other Services | ~$5 |
| **Total** | **~$381** |

### Cost Reduction Options

1. Use preemptible instances for dev/staging
2. Reduce disk sizes if not needed
3. Use standard disks instead of SSD
4. Implement lifecycle policies for storage
5. Use committed use discounts

## Compliance Evidence

Evidence is automatically collected in:
- Local: `terraform/gcp-gitea/evidence/`
- GCS: `gs://evidence-bucket/`

Evidence includes:
- Deployment configurations
- Security control implementations
- Change logs
- Audit trails

## Troubleshooting

### Common Issues

1. **Instance not accessible**:
   ```bash
   # Check instance status
   gcloud compute instances describe gitea-vm --zone=ZONE

   # View startup script logs
   gcloud compute instances get-serial-port-output gitea-vm --zone=ZONE
   ```

2. **Gitea not starting**:
   ```bash
   # SSH to instance
   gcloud compute ssh gitea-vm --zone=ZONE --tunnel-through-iap

   # Check Docker logs
   docker logs gitea
   docker logs gitea-postgres
   ```

3. **Storage issues**:
   ```bash
   # Check disk usage
   df -h

   # Check bucket access
   gsutil ls gs://BUCKET_NAME/
   ```

## Security Best Practices

1. **Regular Updates**: Enable automatic security updates
2. **Secret Rotation**: Rotate passwords quarterly
3. **Access Reviews**: Review IAM permissions monthly
4. **Backup Testing**: Test restore procedures quarterly
5. **Security Scanning**: Run vulnerability scans monthly
6. **Audit Reviews**: Review audit logs weekly
7. **Incident Response**: Document and test procedures

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review Cloud Logging for errors
3. Consult the Gitea documentation
4. Contact your platform team

## License

This Terraform module is provided as-is for CMMC 2.0 Level 2 compliance implementations.

## Acknowledgments

- Gitea community for the excellent Git platform
- Google Cloud for robust infrastructure services
- NIST for comprehensive security guidelines
- CIS for security benchmarks