# Containerized Gitea Deployment Guide

## Overview

This guide covers deploying Gitea as a containerized service integrated with the complete DevSecOps platform. The containerized approach provides:

- **Complete Portability** - Move Gitea between environments easily
- **Consistent Configuration** - Infrastructure as Code
- **Easy Backup/Restore** - Volume-based data management
- **Resource Control** - CPU and memory limits
- **Network Isolation** - Secure network segmentation
- **Full Integration** - Seamless connection with all platform components

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Host                              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  gitea_default Network (Public)                      │  │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────────┐        │  │
│  │  │  Gitea  │  │ Runner  │  │  Caddy (TLS) │        │  │
│  │  │  :3000  │  │  (DinD) │  │   :443/:80   │        │  │
│  │  └────┬────┘  └─────────┘  └──────────────┘        │  │
│  └───────┼───────────────────────────────────────────────┘  │
│          │                                                   │
│  ┌───────┼───────────────────────────────────────────────┐  │
│  │  gitea_data Network (Private - No Internet)          │  │
│  │  ┌────┴─────┐                                        │  │
│  │  │PostgreSQL│                                        │  │
│  │  │  :5432   │                                        │  │
│  │  └──────────┘                                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  gitea_monitoring Network                            │  │
│  │  Connects to: Prometheus, Grafana                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Gitea Server
- **Image:** `gitea/gitea:1.21-rootless`
- **Purpose:** Git repository hosting with web UI
- **Features:**
  - Rootless container for security
  - PostgreSQL backend
  - Git LFS support
  - Built-in Actions (CI/CD)
  - Prometheus metrics
  - OAuth2 support

### 2. PostgreSQL Database
- **Image:** `postgres:15-alpine`
- **Purpose:** Data persistence for Gitea
- **Features:**
  - Isolated on private network
  - Health checks
  - Automated backups
  - Volume-based storage

### 3. Gitea Actions Runner
- **Image:** `gitea/act_runner:latest`
- **Purpose:** Execute CI/CD pipelines
- **Features:**
  - Docker-in-Docker support
  - Multiple concurrent jobs
  - Security scanning integration
  - Caching for faster builds

### 4. Caddy Reverse Proxy (Optional)
- **Image:** `caddy:2-alpine`
- **Purpose:** TLS termination and HTTPS
- **Features:**
  - Automatic HTTPS with Let's Encrypt
  - HTTP/2 support
  - Security headers
  - Access logging

## Quick Start

### Prerequisites

```bash
# Install Docker and Docker Compose
sudo apt-get update
sudo apt-get install -y docker.io docker-compose

# Start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add your user to docker group (logout/login required)
sudo usermod -aG docker $USER
```

### Deployment

```bash
# Navigate to project directory
cd /home/notme/Desktop/gitea

# Run automated setup script
./scripts/setup-gitea-container.sh

# The script will:
# 1. Check dependencies
# 2. Generate secure secrets
# 3. Create .env.gitea configuration
# 4. Deploy containers
# 5. Wait for Gitea to start
# 6. Guide you through runner setup
```

### Manual Deployment

If you prefer manual control:

```bash
# 1. Copy environment template
cp .env.gitea.template .env.gitea

# 2. Edit configuration
nano .env.gitea

# 3. Generate secrets
GITEA_SECRET_KEY=$(openssl rand -hex 32)
GITEA_INTERNAL_TOKEN=$(openssl rand -hex 32)
# ... (update .env.gitea with generated values)

# 4. Create directories
mkdir -p backups/postgres-gitea logs/gitea

# 5. Deploy containers
docker-compose -f docker-compose-gitea.yml up -d

# 6. Check status
docker-compose -f docker-compose-gitea.yml ps

# 7. View logs
docker-compose -f docker-compose-gitea.yml logs -f gitea
```

## Configuration

### Environment Variables

All configuration is in `.env.gitea`:

| Variable | Description | Example |
|----------|-------------|---------|
| `GITEA_DOMAIN` | Your domain or IP | `git.example.com` |
| `GITEA_ROOT_URL` | Full URL with protocol | `https://git.example.com/` |
| `GITEA_HTTP_PORT` | HTTP port (external) | `3000` |
| `GITEA_SSH_PORT` | SSH port (external) | `2222` |
| `POSTGRES_GITEA_PASSWORD` | Database password | (auto-generated) |
| `GITEA_SECRET_KEY` | Encryption key (64 chars) | (auto-generated) |
| `GITEA_ADMIN_USER` | Initial admin username | `admin` |
| `GITEA_ADMIN_PASSWORD` | Initial admin password | (set during setup) |

### Runner Configuration

Configure the Actions runner in `config/runner-config.yaml`:

```yaml
runner:
  name: docker-runner-1
  capacity: 4  # Concurrent jobs
  timeout: 3h  # Max job duration

cache:
  enabled: true
  max_size: 10GB
  retention_days: 7

container:
  privileged: false  # Disable for security
  valid_volumes:
    - /workspace
    - /data
```

### Network Configuration

Three Docker networks are created:

1. **gitea_default** (bridge)
   - Public-facing services
   - Gitea, Runner, Caddy
   - Connected to other platform components

2. **gitea_data** (bridge, internal)
   - Database tier only
   - No external internet access
   - Isolated for security

3. **gitea_monitoring** (bridge)
   - Prometheus/Grafana metrics
   - Monitoring integration

## Actions Runner Setup

### Step 1: Generate Registration Token

1. Access Gitea: `http://localhost:3000`
2. Login as admin
3. Navigate to: **Admin Panel** → **Actions** → **Runners**
4. Click **"Create Registration Token"**
5. Copy the generated token

### Step 2: Register Runner

**Option A: During setup script**
- The script will prompt for the token
- Runner registers automatically

**Option B: Manual registration**

```bash
# Update .env.gitea with token
nano .env.gitea
# Set: GITEA_RUNNER_TOKEN=your-token-here

# Restart runner
docker-compose -f docker-compose-gitea.yml restart gitea-runner

# Check runner logs
docker-compose -f docker-compose-gitea.yml logs -f gitea-runner
```

### Step 3: Verify Runner

1. Return to **Admin Panel** → **Actions** → **Runners**
2. You should see "docker-runner-1" with status **"idle"**
3. Test with a sample workflow

## Integration with Platform Components

### SonarQube Integration

```bash
# SonarQube connects to Gitea via gitea_default network
# Update workflow file (.gitea/workflows/sonarqube-scan.yml):
env:
  SONARQUBE_URL: http://sonarqube:9000
  GITEA_URL: http://gitea:3000
```

### n8n Webhook Integration

```bash
# Configure Gitea webhook to n8n
# Webhook URL: http://n8n:5678/webhook/security-events

# In Gitea UI:
# Repository → Settings → Webhooks → Add Webhook
# URL: http://n8n:5678/webhook/security-events
# Content Type: application/json
# Secret: (from .env.gitea N8N_API_KEY)
# Events: Push, Pull Request, Issues
```

### Atlantis GitOps Integration

```bash
# Configure Gitea webhook to Atlantis
# Webhook URL: http://atlantis:4141/events

# In Gitea UI:
# Repository → Settings → Webhooks → Add Webhook
# URL: http://atlantis:4141/events
# Content Type: application/json
# Secret: (from .env.gitea ATLANTIS_WEBHOOK_SECRET)
# Events: Pull Request, Issue Comment
```

### Prometheus Monitoring

```bash
# Gitea exposes metrics at /metrics endpoint
# Prometheus scrapes with authentication

# Add to prometheus.yml:
scrape_configs:
  - job_name: 'gitea'
    static_configs:
      - targets: ['gitea:3000']
    metrics_path: '/metrics'
    bearer_token: 'YOUR_GITEA_METRICS_TOKEN'
```

## TLS/HTTPS Setup

### Development (Self-Signed)

```bash
# Deploy with Caddy using self-signed certs
docker-compose --profile tls -f docker-compose-gitea.yml up -d

# Access via HTTPS (accept browser warning)
# https://localhost
```

### Production (Let's Encrypt)

1. Edit `config/Caddyfile.gitea`:

```caddyfile
{$GITEA_DOMAIN} {
    tls {
        email {$GITEA_ADMIN_EMAIL}
    }
    # ... rest of config
}
```

2. Update `.env.gitea`:

```bash
GITEA_DOMAIN=git.yourdomain.com
GITEA_ROOT_URL=https://git.yourdomain.com/
GITEA_COOKIE_SECURE=true
```

3. Deploy:

```bash
docker-compose --profile tls -f docker-compose-gitea.yml up -d
```

## Backup and Restore

### Automated Backups

Backups are stored in `backups/postgres-gitea/`:

```bash
# Manual backup
docker exec postgres-gitea pg_dump -U gitea gitea | gzip > backups/postgres-gitea/gitea-$(date +%Y%m%d).sql.gz

# Backup volumes
docker run --rm -v gitea_data:/data -v $(pwd)/backups:/backup alpine tar czf /backup/gitea-data-$(date +%Y%m%d).tar.gz /data
```

### Restore from Backup

```bash
# Stop services
docker-compose -f docker-compose-gitea.yml down

# Restore database
gunzip < backups/postgres-gitea/gitea-20240115.sql.gz | docker exec -i postgres-gitea psql -U gitea -d gitea

# Restore volumes
docker run --rm -v gitea_data:/data -v $(pwd)/backups:/backup alpine tar xzf /backup/gitea-data-20240115.tar.gz -C /

# Start services
docker-compose -f docker-compose-gitea.yml up -d
```

## Troubleshooting

### Gitea Won't Start

```bash
# Check logs
docker-compose -f docker-compose-gitea.yml logs gitea

# Common issues:
# 1. Database not ready
docker-compose -f docker-compose-gitea.yml logs postgres-gitea

# 2. Port conflicts
sudo netstat -tulpn | grep -E '3000|2222'

# 3. Permission issues (rootless container)
sudo chown -R 1000:1000 volumes/gitea_data
```

### Runner Not Connecting

```bash
# Check runner logs
docker-compose -f docker-compose-gitea.yml logs gitea-runner

# Verify registration token
cat .env.gitea | grep GITEA_RUNNER_TOKEN

# Re-register runner
docker-compose -f docker-compose-gitea.yml restart gitea-runner
```

### Webhook Failures

```bash
# Test webhook manually
curl -X POST http://localhost:3000/api/v1/repos/owner/repo/hooks \
  -H "Authorization: token YOUR_GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "gitea",
    "config": {
      "url": "http://n8n:5678/webhook/test",
      "content_type": "json"
    },
    "events": ["push"],
    "active": true
  }'

# Check network connectivity
docker exec gitea ping n8n
docker exec gitea curl http://n8n:5678/healthz
```

## Security Best Practices

1. **Change Default Passwords**
   ```bash
   # Update .env.gitea
   GITEA_ADMIN_PASSWORD=<strong-password-14+chars>
   POSTGRES_GITEA_PASSWORD=<strong-password>
   ```

2. **Disable Registration** (Production)
   ```bash
   GITEA_DISABLE_REGISTRATION=true
   ```

3. **Enable HTTPS**
   ```bash
   # Use Caddy with Let's Encrypt
   docker-compose --profile tls -f docker-compose-gitea.yml up -d
   ```

4. **Restrict Runner Privileges**
   ```yaml
   # config/runner-config.yaml
   security:
     block_privileged: true
     resource_limits:
       cpu: 4
       memory: 8G
   ```

5. **Regular Updates**
   ```bash
   # Pull latest images
   docker-compose -f docker-compose-gitea.yml pull

   # Recreate containers
   docker-compose -f docker-compose-gitea.yml up -d
   ```

## Monitoring

### Health Checks

```bash
# Check all services
docker-compose -f docker-compose-gitea.yml ps

# Health check endpoints
curl http://localhost:3000/api/healthz  # Gitea
curl http://localhost:9090/metrics      # Prometheus (if enabled)
```

### Resource Usage

```bash
# Monitor containers
docker stats gitea postgres-gitea gitea-runner

# Disk usage
docker system df
du -sh volumes/gitea_data
```

### Logs

```bash
# Follow all logs
docker-compose -f docker-compose-gitea.yml logs -f

# Specific service logs
docker-compose -f docker-compose-gitea.yml logs -f gitea
docker-compose -f docker-compose-gitea.yml logs -f postgres-gitea
docker-compose -f docker-compose-gitea.yml logs -f gitea-runner
```

## Performance Tuning

### Database Optimization

Edit `docker-compose-gitea.yml` PostgreSQL environment:

```yaml
environment:
  # Increase shared buffers
  POSTGRES_INITDB_ARGS: "-c shared_buffers=256MB -c max_connections=200"
```

### Runner Performance

Adjust `config/runner-config.yaml`:

```yaml
runner:
  capacity: 8  # Increase concurrent jobs

cache:
  max_size: 20GB  # Larger cache for faster builds
```

### Resource Limits

Modify `docker-compose-gitea.yml` deploy section:

```yaml
deploy:
  resources:
    limits:
      cpus: '8'      # Increase CPU
      memory: 8G     # Increase RAM
```

## Migration from Existing Gitea

If you have an existing Gitea installation:

```bash
# 1. Backup existing Gitea
gitea dump -c /path/to/app.ini

# 2. Stop existing Gitea
sudo systemctl stop gitea

# 3. Extract dump
unzip gitea-dump-*.zip

# 4. Import to containerized PostgreSQL
cat gitea-db.sql | docker exec -i postgres-gitea psql -U gitea -d gitea

# 5. Copy repositories and data
cp -r gitea-repo/* volumes/gitea_data/git/repositories/
cp -r gitea-files/* volumes/gitea_data/

# 6. Fix permissions
sudo chown -R 1000:1000 volumes/gitea_data

# 7. Start containerized Gitea
docker-compose -f docker-compose-gitea.yml up -d
```

## Next Steps

1. **Deploy Platform Components**
   ```bash
   make deploy-phase1a    # Security scanners
   make deploy-n8n        # Workflow automation
   make monitoring-deploy # Prometheus + Grafana
   make atlantis-deploy   # GitOps
   ```

2. **Configure Webhooks**
   - SonarQube quality gate notifications
   - n8n security event processing
   - Atlantis Terraform automation

3. **Set Up CI/CD Pipelines**
   - Create `.gitea/workflows/` in repositories
   - Configure security scanning workflows
   - Enable automated testing

4. **Enable Compliance Monitoring**
   - Configure evidence collection
   - Set up Grafana dashboards
   - Enable audit logging

## Support

- **Container Logs:** `docker-compose -f docker-compose-gitea.yml logs`
- **Documentation:** `/home/notme/Desktop/gitea/docs/`
- **Gitea Docs:** https://docs.gitea.io/
- **GitHub Issues:** https://github.com/go-gitea/gitea/issues

---

**Platform Version:** 1.0.0
**Last Updated:** 2025-10-05
