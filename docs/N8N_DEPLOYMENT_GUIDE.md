# n8n Deployment Guide for DevSecOps Platform

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Configuration](#configuration)
- [Security Hardening](#security-hardening)
- [Backup and Recovery](#backup-and-recovery)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## Overview

n8n is the workflow automation platform that powers our DevSecOps security event processing, compliance automation, and incident response workflows. This guide covers deploying n8n with PostgreSQL backend, TLS termination via Caddy, and integration with Google Chat, Gitea, and GCP services.

### Architecture Components

```
┌─────────────┐     ┌──────────┐     ┌────────────┐
│   Gitea     │────▶│  Caddy   │────▶│    n8n     │
│  Webhooks   │     │  (TLS)   │     │  Workflow  │
└─────────────┘     └──────────┘     └────────────┘
                                             │
                    ┌────────────────────────┴────────────┐
                    ▼                ▼                    ▼
            ┌────────────┐   ┌────────────┐      ┌────────────┐
            │ PostgreSQL │   │   Redis    │      │    GCS     │
            │  Database  │   │   Cache    │      │  Evidence  │
            └────────────┘   └────────────┘      └────────────┘
```

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+ or RHEL 8+)
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+
- **CPU**: Minimum 2 cores, recommended 4 cores
- **RAM**: Minimum 4GB, recommended 8GB
- **Storage**: 20GB for n8n data and PostgreSQL

### Network Requirements

- **Ports**:
  - 80/tcp: HTTP (redirects to HTTPS)
  - 443/tcp: HTTPS
  - 5678/tcp: n8n (internal only)
  - 5432/tcp: PostgreSQL (internal only)

### Domain and SSL

- Valid domain name pointing to your server
- Email address for Let's Encrypt certificates

## Quick Start

### 1. Clone and Setup

```bash
# Navigate to project directory
cd /home/notme/Desktop/gitea

# Make scripts executable
chmod +x scripts/*.sh

# Run automated setup
./scripts/setup-n8n.sh
```

### 2. Configure Credentials

```bash
# Interactive credential configuration
./scripts/configure-n8n-credentials.sh
```

### 3. Test Installation

```bash
# Run integration tests
./scripts/test-n8n-workflows.sh all
```

## Detailed Installation

### Step 1: Environment Preparation

1. **Copy environment template**:
```bash
cp .env.n8n.template .env
```

2. **Edit environment variables**:
```bash
# Required configurations
N8N_HOST=n8n.yourdomain.com
ACME_EMAIL=admin@yourdomain.com

# Generate secure passwords
openssl rand -hex 16  # For N8N_ENCRYPTION_KEY
openssl rand -base64 32  # For other passwords
```

### Step 2: Deploy Stack

```bash
# Start all services
docker-compose -f docker-compose-n8n.yml up -d

# Check service health
docker-compose -f docker-compose-n8n.yml ps

# View logs
docker-compose -f docker-compose-n8n.yml logs -f
```

### Step 3: Initial Configuration

1. **Access n8n UI**:
   - URL: `https://n8n.yourdomain.com`
   - Username: `admin` (or from .env)
   - Password: (from .env file)

2. **Import Workflow**:
   - Navigate to Workflows
   - Click "Import from File"
   - Select `/n8n/workflows/devsecops-security-automation.json`

3. **Configure Credentials**:
   - Go to Settings → Credentials
   - Add required credentials:
     - Google Chat Webhooks
     - Gitea API
     - GCP Service Account
     - SMTP Email
     - Webhook API Key

## Configuration

### Google Chat Webhooks

1. **Create Google Chat Webhook**:
   - Open Google Chat
   - Create or select a space
   - Click space name → "Apps & integrations"
   - Click "Webhooks" → "Add webhook"
   - Name: "DevSecOps Security Alerts"
   - Copy the webhook URL

2. **Configure in n8n**:
   - Add HTTP Request credential
   - Type: Header Auth
   - Name: `X-API-Key`
   - Value: Your webhook token

### Gitea Integration

1. **Generate Gitea API Token**:
```bash
# In Gitea UI
Settings → Applications → Generate Token
# Scopes: repo, admin:repo_hook
```

2. **Configure Gitea Webhooks**:
```bash
# Repository Settings → Webhooks → Add Webhook
URL: https://n8n.yourdomain.com/webhook/security-events
Content Type: application/json
Secret: <your-webhook-api-key>
Events: Push, Pull Request, Issues
```

### GCP Service Account

1. **Create Service Account**:
```bash
# Using gcloud CLI
gcloud iam service-accounts create n8n-automation \
    --display-name="n8n Automation Service Account"

# Grant permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:n8n-automation@PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"

# Create key
gcloud iam service-accounts keys create key.json \
    --iam-account=n8n-automation@PROJECT_ID.iam.gserviceaccount.com
```

2. **Configure in n8n**:
   - Create Google API credential
   - Upload service account JSON

### Email Configuration

For Gmail with App Password:

1. **Enable 2FA** in Google Account
2. **Generate App Password**:
   - Google Account → Security → 2-Step Verification
   - App passwords → Generate
3. **Configure SMTP**:
   - Host: smtp.gmail.com
   - Port: 587
   - User: your-email@gmail.com
   - Password: [app password]

## Security Hardening

### 1. Network Security

```yaml
# Update docker-compose-n8n.yml
services:
  n8n:
    ports:
      - "127.0.0.1:5678:5678"  # Bind to localhost only

  postgres:
    ports:
      - "127.0.0.1:5432:5432"  # Bind to localhost only
```

### 2. Authentication

**Enable OAuth2 with Google**:
```env
N8N_AUTH_TYPE=google
N8N_AUTH_GOOGLE_ENABLED=true
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
```

### 3. Webhook Security

**Implement IP Whitelisting**:
```nginx
# In Caddy configuration
@webhook_whitelist {
    path /webhook/*
    remote_ip 192.168.1.0/24 10.0.0.0/8
}

handle @webhook_whitelist {
    reverse_proxy n8n:5678
}
```

### 4. Database Encryption

```sql
-- Enable encryption at rest
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET ssl_cert_file = '/path/to/server.crt';
ALTER SYSTEM SET ssl_key_file = '/path/to/server.key';
```

### 5. Audit Logging

All workflow executions are logged with:
- Execution ID
- Timestamp
- User/trigger
- Success/failure status
- Input/output data (configurable)

## Backup and Recovery

### Automated Backups

Create backup script `/scripts/backup-n8n.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/backups/n8n"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup PostgreSQL
docker exec postgres pg_dump -U n8n n8n | gzip > "$BACKUP_DIR/db_$TIMESTAMP.sql.gz"

# Backup n8n data
docker run --rm -v n8n_data:/data -v $BACKUP_DIR:/backup \
    alpine tar czf /backup/n8n_data_$TIMESTAMP.tar.gz /data

# Backup workflows
cp -r /home/notme/Desktop/gitea/n8n/workflows "$BACKUP_DIR/workflows_$TIMESTAMP"

# Retain last 30 days
find $BACKUP_DIR -mtime +30 -delete
```

### Schedule Backups

```bash
# Add to crontab
0 2 * * * /home/notme/Desktop/gitea/scripts/backup-n8n.sh
```

### Recovery Process

```bash
# Stop services
docker-compose -f docker-compose-n8n.yml down

# Restore database
gunzip < backup.sql.gz | docker exec -i postgres psql -U n8n n8n

# Restore n8n data
docker run --rm -v n8n_data:/data -v /backups:/backup \
    alpine tar xzf /backup/n8n_data_backup.tar.gz -C /

# Start services
docker-compose -f docker-compose-n8n.yml up -d
```

## Troubleshooting

### Common Issues

#### 1. n8n Won't Start

```bash
# Check logs
docker-compose -f docker-compose-n8n.yml logs n8n

# Verify database connection
docker exec -it postgres psql -U n8n -d n8n -c "SELECT 1;"

# Check port availability
netstat -tlnp | grep 5678
```

#### 2. Webhook Not Receiving Events

```bash
# Test webhook directly
curl -X POST https://n8n.yourdomain.com/webhook/security-events \
    -H "X-API-Key: your-api-key" \
    -H "Content-Type: application/json" \
    -d '{"event_type":"test"}'

# Check Caddy logs
docker-compose -f docker-compose-n8n.yml logs caddy
```

#### 3. Workflow Execution Failures

```bash
# Access n8n container
docker exec -it gitea-n8n-1 /bin/sh

# Check execution logs
ls -la /home/node/.n8n/executionLogs/

# View specific execution
cat /home/node/.n8n/executionLogs/execution_[id].log
```

#### 4. Database Issues

```bash
# Check database health
docker exec postgres pg_isready -U n8n

# Vacuum and analyze
docker exec postgres psql -U n8n -d n8n -c "VACUUM ANALYZE;"

# Check table sizes
docker exec postgres psql -U n8n -d n8n -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```

### Performance Tuning

#### 1. PostgreSQL Optimization

```sql
-- Update postgresql.conf
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET work_mem = '4MB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
```

#### 2. n8n Configuration

```env
# Optimize execution
EXECUTIONS_PROCESS=main
EXECUTIONS_TIMEOUT=900
N8N_PAYLOAD_SIZE_MAX=16

# Worker configuration for high load
EXECUTIONS_MODE=queue
EXECUTIONS_WORKER_COUNT=4
```

## Maintenance

### Daily Tasks

```bash
# Check service health
docker-compose -f docker-compose-n8n.yml ps

# Review execution logs
docker-compose -f docker-compose-n8n.yml logs --tail=100
```

### Weekly Tasks

```bash
# Clean old executions
docker exec gitea-n8n-1 n8n executionData:prune --days 14

# Update containers
docker-compose -f docker-compose-n8n.yml pull
docker-compose -f docker-compose-n8n.yml up -d
```

### Monthly Tasks

```bash
# Database maintenance
docker exec postgres psql -U n8n -d n8n -c "VACUUM FULL ANALYZE;"

# Review and rotate logs
find /var/log/n8n -mtime +30 -delete

# Security updates
docker-compose -f docker-compose-n8n.yml down
docker system prune -a --volumes
docker-compose -f docker-compose-n8n.yml up -d
```

## Monitoring

### Health Checks

```bash
# Create monitoring script
cat > /scripts/monitor-n8n.sh << 'EOF'
#!/bin/bash

# Check n8n health
if ! curl -s http://localhost:5678/healthz | grep -q "ok"; then
    echo "n8n is unhealthy"
    # Send alert
fi

# Check database
if ! docker exec postgres pg_isready -U n8n; then
    echo "PostgreSQL is unhealthy"
    # Send alert
fi

# Check disk usage
USAGE=$(df -h /var/lib/docker | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $USAGE -gt 80 ]; then
    echo "Disk usage critical: $USAGE%"
    # Send alert
fi
EOF

chmod +x /scripts/monitor-n8n.sh

# Add to crontab
*/5 * * * * /scripts/monitor-n8n.sh
```

### Prometheus Metrics

n8n exports metrics at `/metrics` endpoint:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: '/metrics'
```

## High Availability Setup

For production environments requiring HA:

### 1. Database Replication

```yaml
# Add PostgreSQL replica
postgres-replica:
  image: postgres:15-alpine
  environment:
    POSTGRES_REPLICATION_MODE: slave
    POSTGRES_MASTER_HOST: postgres
    POSTGRES_REPLICATION_USER: replicator
    POSTGRES_REPLICATION_PASSWORD: ${REPLICATION_PASSWORD}
```

### 2. n8n Clustering

```yaml
# Scale n8n workers
services:
  n8n-main:
    environment:
      EXECUTIONS_MODE: queue
      EXECUTIONS_QUEUE: redis

  n8n-worker:
    image: n8nio/n8n
    command: worker
    deploy:
      replicas: 3
```

### 3. Load Balancing

```yaml
# Caddy load balancing
reverse_proxy {
    to n8n-1:5678 n8n-2:5678 n8n-3:5678
    lb_policy round_robin
    health_uri /healthz
}
```

## Support and Resources

- **n8n Documentation**: https://docs.n8n.io
- **Community Forum**: https://community.n8n.io
- **GitHub Issues**: https://github.com/n8n-io/n8n/issues
- **Internal Wiki**: Document your organization-specific configurations

## License

This deployment guide is part of the DevSecOps platform implementation.
n8n is licensed under the [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md).