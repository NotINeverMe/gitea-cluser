# Monitoring Stack Deployment Guide

## CMMC 2.0 and NIST Compliance
- **CMMC 2.0**: AU.L2-3.3.1, SI.L2-3.14.4, SI.L2-3.14.6
- **NIST SP 800-171**: 3.3.1, 3.3.2, 3.14.4, 3.14.6
- **NIST SP 800-53**: AU-6, SI-4

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Deployment Steps](#deployment-steps)
4. [Configuration](#configuration)
5. [Security Hardening](#security-hardening)
6. [High Availability Setup](#high-availability-setup)
7. [Backup and Recovery](#backup-and-recovery)
8. [Troubleshooting](#troubleshooting)
9. [Compliance Evidence](#compliance-evidence)

## Prerequisites

### System Requirements
- **CPU**: Minimum 4 cores, recommended 8 cores
- **Memory**: Minimum 8GB RAM, recommended 16GB RAM
- **Storage**: Minimum 100GB SSD for metrics retention (90 days)
- **Network**: Stable network connection with low latency

### Software Requirements
- Docker Engine 20.10+
- Docker Compose 2.0+
- Git 2.30+
- OpenSSL (for certificate generation)
- jq (for JSON processing)

### Access Requirements
- Administrative access to host system
- Network access to monitored services
- Google Cloud Platform account (for OAuth2 and GCP metrics)
- Google Chat webhook URLs for alerting

## Architecture Overview

```mermaid
graph TB
    subgraph "Data Sources"
        A[Gitea]
        B[SonarQube]
        C[n8n]
        D[Trivy]
        E[Atlantis]
        F[GCP]
    end

    subgraph "Exporters"
        G[Node Exporter]
        H[Blackbox Exporter]
        I[SonarQube Exporter]
        J[Security Scan Exporter]
        K[Compliance Exporter]
        L[Stackdriver Exporter]
    end

    subgraph "Monitoring Stack"
        M[Prometheus]
        N[Alertmanager]
        O[Grafana]
        P[PostgreSQL]
    end

    subgraph "Outputs"
        Q[Google Chat]
        R[Dashboards]
        S[Evidence Collection]
    end

    A --> M
    B --> I --> M
    C --> M
    D --> J --> M
    E --> M
    F --> L --> M
    G --> M
    H --> M
    K --> M

    M --> N --> Q
    M --> O
    P --> O
    O --> R
    M --> S
```

## Deployment Steps

### 1. Clone Repository and Navigate to Project

```bash
git clone https://github.com/your-org/gitea-devsecops.git
cd gitea-devsecops
```

### 2. Configure Environment Variables

Create and configure the environment file:

```bash
cp monitoring/.env.example monitoring/.env
vim monitoring/.env
```

Required variables:
```env
# Grafana Admin
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<strong-password>

# OAuth2 (Google)
OAUTH_CLIENT_ID=<your-client-id>.apps.googleusercontent.com
OAUTH_CLIENT_SECRET=<your-client-secret>
ALLOWED_DOMAINS=yourdomain.com

# Google Chat Webhooks
GCHAT_WEBHOOK_MONITORING=https://chat.googleapis.com/v1/spaces/...
GCHAT_WEBHOOK_SECURITY=https://chat.googleapis.com/v1/spaces/...
GCHAT_WEBHOOK_COMPLIANCE=https://chat.googleapis.com/v1/spaces/...

# Service Tokens
SONARQUBE_TOKEN=<sonarqube-api-token>
```

### 3. Run Setup Script

Execute the automated setup script:

```bash
chmod +x scripts/setup-monitoring.sh
sudo ./scripts/setup-monitoring.sh
```

The script will:
- Create required directories
- Build custom exporters
- Generate self-signed certificates
- Deploy the monitoring stack
- Verify deployment
- Generate compliance evidence

### 4. Manual Deployment (Alternative)

If you prefer manual deployment:

```bash
# Create directories
mkdir -p monitoring/data/{prometheus,grafana,alertmanager,postgres}

# Build exporters
cd monitoring/exporters
docker build -f Dockerfile.sonarqube -t sonarqube-exporter:latest .
docker build -f Dockerfile.security -t security-scan-exporter:latest .
docker build -f Dockerfile.compliance -t compliance-exporter:latest .
cd ../..

# Deploy stack
cd monitoring
docker-compose -f docker-compose-monitoring.yml up -d
```

### 5. Verify Deployment

Check service health:

```bash
# Check running containers
docker-compose -f monitoring/docker-compose-monitoring.yml ps

# Test endpoints
curl -s http://localhost:9090/-/healthy  # Prometheus
curl -s http://localhost:3000/api/health  # Grafana
curl -s http://localhost:9093/-/healthy   # Alertmanager
```

## Configuration

### Prometheus Configuration

Edit `monitoring/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'devsecops-monitor'
    environment: 'production'

# Add new scrape targets
scrape_configs:
  - job_name: 'custom-service'
    static_configs:
      - targets: ['service:port']
```

Reload configuration:

```bash
curl -X POST http://localhost:9090/-/reload
```

### Alertmanager Configuration

Edit `monitoring/alertmanager/alertmanager.yml`:

```yaml
receivers:
  - name: 'custom-receiver'
    webhook_configs:
      - url: 'https://your-webhook-url'
```

### Grafana Configuration

#### Add Data Source Programmatically

```bash
curl -X POST http://admin:password@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }'
```

#### Import Dashboard

```bash
curl -X POST http://admin:password@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana/dashboards/devsecops-platform-overview.json
```

## Security Hardening

### 1. Enable TLS/HTTPS

Generate proper certificates:

```bash
# Generate CA
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem

# Generate server certificate
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=monitoring.example.com" -sha256 -new -key server-key.pem -out server.csr
openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem -out server-cert.pem
```

### 2. Configure Nginx Reverse Proxy

```nginx
server {
    listen 443 ssl http2;
    server_name monitoring.example.com;

    ssl_certificate /etc/nginx/certs/server-cert.pem;
    ssl_certificate_key /etc/nginx/certs/server-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 3. Configure Firewall Rules

```bash
# Allow only necessary ports
sudo ufw allow 443/tcp  # HTTPS
sudo ufw allow 9090/tcp from 10.0.0.0/8  # Prometheus (internal only)
sudo ufw allow 3000/tcp from 10.0.0.0/8  # Grafana (internal only)
sudo ufw enable
```

### 4. Enable Authentication

#### Prometheus Basic Auth

Create htpasswd file:

```bash
htpasswd -c /etc/prometheus/.htpasswd admin
```

Update Prometheus configuration:

```yaml
# In docker-compose.yml
command:
  - '--web.config.file=/etc/prometheus/web.yml'
```

Create web.yml:

```yaml
basic_auth_users:
  admin: $2y$10$... # bcrypt hash
```

## High Availability Setup

### Prometheus HA Configuration

Deploy multiple Prometheus instances:

```yaml
services:
  prometheus-1:
    image: prom/prometheus:v2.47.0
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'
      - '--web.external-url=http://prometheus-1:9090'
    volumes:
      - prometheus_data_1:/prometheus

  prometheus-2:
    image: prom/prometheus:v2.47.0
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'
      - '--web.external-url=http://prometheus-2:9090'
    volumes:
      - prometheus_data_2:/prometheus
```

### Grafana HA Configuration

Configure Grafana for HA:

```ini
[database]
type = postgres
host = postgres-primary:5432,postgres-standby:5432

[session]
provider = postgres
provider_config = user=grafana password=password host=postgres-primary port=5432 dbname=grafana sslmode=require

[remote_cache]
type = redis
connstr = redis-cluster:6379
```

## Backup and Recovery

### Automated Backups

Schedule backup script:

```bash
# Add to crontab
0 2 * * * /home/user/gitea-devsecops/scripts/backup-grafana.sh >> /var/log/grafana-backup.log 2>&1
```

### Manual Backup

```bash
# Backup Prometheus data
docker run --rm -v monitoring_prometheus_data:/data -v $(pwd):/backup alpine \
  tar czf /backup/prometheus-backup-$(date +%Y%m%d).tar.gz /data

# Backup Grafana
./scripts/backup-grafana.sh
```

### Recovery Procedure

```bash
# Restore Prometheus
docker run --rm -v monitoring_prometheus_data:/data -v $(pwd):/backup alpine \
  tar xzf /backup/prometheus-backup-20240101.tar.gz -C /

# Restore Grafana
tar xzf grafana-backup-20240101.tar.gz
docker exec grafana-postgres psql -U grafana < grafana.sql
```

## Troubleshooting

### Common Issues

#### 1. Prometheus Not Scraping Targets

Check target status:
```bash
curl http://localhost:9090/api/v1/targets
```

Verify network connectivity:
```bash
docker exec prometheus curl -v http://target:port/metrics
```

#### 2. Grafana Database Connection Issues

Check PostgreSQL:
```bash
docker logs grafana-postgres
docker exec grafana-postgres psql -U grafana -c "SELECT 1"
```

#### 3. Alertmanager Not Sending Alerts

Test webhook:
```bash
curl -X POST https://chat.googleapis.com/v1/spaces/... \
  -H "Content-Type: application/json" \
  -d '{"text": "Test alert"}'
```

Check Alertmanager logs:
```bash
docker logs alertmanager
```

### Debug Commands

```bash
# Check Prometheus configuration
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Check alert rules
docker exec prometheus promtool check rules /etc/prometheus/alerts/*.yml

# View Prometheus metrics
curl -s http://localhost:9090/api/v1/query?query=up

# Check Grafana API
curl -s http://admin:password@localhost:3000/api/org

# Test exporter endpoints
curl -s http://localhost:9200/metrics  # SonarQube exporter
curl -s http://localhost:9201/metrics  # Security scan exporter
curl -s http://localhost:9202/metrics  # Compliance exporter
```

## Compliance Evidence

### Evidence Collection

Evidence is automatically collected in:
- `/home/notme/Desktop/gitea/compliance/evidence/monitoring/`

### Evidence Format

```json
{
  "timestamp": "2024-01-01T00:00:00Z",
  "component": "monitoring-stack",
  "action": "deployment",
  "status": "success",
  "compliance": {
    "cmmc": ["AU.L2-3.3.1", "SI.L2-3.14.4"],
    "nist_171": ["3.3.1", "3.14.4"],
    "nist_53": ["AU-6", "SI-4"]
  },
  "hash": "sha256:..."
}
```

### Audit Trail

View audit logs:
```bash
# Prometheus audit log
docker logs prometheus | grep -i audit

# Grafana audit log
docker exec grafana cat /var/log/grafana/grafana.log | grep -i audit

# System audit log
sudo journalctl -u docker --since "1 hour ago"
```

### Compliance Reports

Generate compliance report:
```bash
# Query compliance metrics
curl -s http://localhost:9090/api/v1/query?query=compliance_control_coverage_percent

# Export to CSV
prometheus_2_csv --query 'compliance_control_implemented{framework="cmmc"}' \
  --start "$(date -d '30 days ago' --iso-8601)" \
  --end "$(date --iso-8601)" \
  --output compliance_report.csv
```

## Maintenance

### Regular Tasks

1. **Daily**:
   - Check alert status
   - Review dashboard metrics
   - Verify backup completion

2. **Weekly**:
   - Review and acknowledge alerts
   - Check disk usage
   - Update dashboards if needed

3. **Monthly**:
   - Review and update alert rules
   - Audit user access
   - Update exporters and configurations
   - Test backup restoration

4. **Quarterly**:
   - Security patching
   - Performance tuning
   - Compliance audit
   - Disaster recovery drill

## Support

For issues or questions:
- Check logs: `docker-compose logs -f [service]`
- Review documentation: `/docs/`
- File issue: GitHub Issues
- Contact: devsecops-team@example.com