# DevSecOps Monitoring Stack

## Overview

Production-ready Prometheus + Grafana monitoring stack for the Gitea DevSecOps platform with full CMMC 2.0 and NIST SP 800-171/800-53 compliance support.

## Quick Start

```bash
# Deploy the complete monitoring stack
make monitoring-deploy

# Check service health
make monitoring-health

# View metrics dashboard
open http://localhost:3000  # Default: admin/ChangeMe123!
```

## Architecture

### Components

- **Prometheus**: Time-series metrics database with 90-day retention
- **Grafana**: Visualization and dashboarding with PostgreSQL backend
- **Alertmanager**: Alert routing to Google Chat spaces
- **Custom Exporters**:
  - SonarQube Exporter: Code quality metrics
  - Security Scan Exporter: Trivy/Grype vulnerability metrics
  - Compliance Exporter: CMMC/NIST control implementation metrics
- **Standard Exporters**:
  - Node Exporter: System metrics
  - Blackbox Exporter: Endpoint monitoring
  - Stackdriver Exporter: GCP metrics

### Compliance Features

- **CMMC 2.0 Coverage**: AU.L2-3.3.1, SI.L2-3.14.4, CA.L2-3.12.1, RA.L2-3.11.2
- **NIST SP 800-171**: 3.3.1, 3.3.2, 3.14.4, 3.14.6, 3.12.1, 3.11.2
- **NIST SP 800-53**: AU-6, SI-4, CA-2, CA-7, RA-5
- **90-day metric retention** for audit compliance
- **Evidence collection** with SHA-256 hashing
- **Automated compliance reporting**

## Dashboards

### Pre-configured Dashboards

1. **DevSecOps Platform Overview**: Service health, vulnerabilities, compliance score
2. **Security Scanning Metrics**: Vulnerability trends, CVSS scores, MTTR
3. **Compliance Metrics**: Control coverage, evidence freshness, assessment readiness
4. **CI/CD Pipeline Performance**: Build metrics, security gates, deployment frequency
5. **GCP Resource Utilization**: Compute, storage, API usage, costs
6. **n8n Workflow Execution**: Success rates, execution time, event processing
7. **Packer Build Statistics**: Build metrics, vulnerability scores, CIS compliance
8. **Atlantis GitOps Activity**: Terraform metrics, policy checks, drift detection

## Alerting

### Alert Categories

- **Security Critical**: Vulnerabilities, malware, secrets exposure
- **Compliance Critical**: Evidence collection failures, retention violations
- **Operational Critical**: Service down, disk space, backup failures
- **Cost Warnings**: Budget thresholds, resource optimization

### Google Chat Integration

Alerts are routed to specific Google Chat spaces based on severity:
- `#security-alerts`: Critical security incidents
- `#compliance-alerts`: Compliance violations
- `#monitoring-alerts`: General operational alerts

## Management Commands

### Using Make

```bash
# Deployment
make monitoring-deploy         # Full deployment with setup
make monitoring-start          # Start existing stack
make monitoring-stop           # Stop services
make monitoring-health         # Health check

# Operations
make monitoring-backup         # Backup Grafana
make monitoring-alerts         # View active alerts
make monitoring-metrics        # Show key metrics
make monitoring-compliance     # Generate compliance report

# Maintenance
make monitoring-build          # Rebuild exporters
```

### Direct Docker Commands

```bash
# View logs
docker-compose -f monitoring/docker-compose-monitoring.yml logs -f prometheus

# Restart service
docker-compose -f monitoring/docker-compose-monitoring.yml restart grafana

# Execute commands
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml
```

## Configuration

### Environment Variables

Edit `monitoring/.env`:

```env
# Grafana
GRAFANA_ADMIN_PASSWORD=<strong-password>
GRAFANA_DOMAIN=monitoring.example.com

# OAuth2/Google
OAUTH_CLIENT_ID=<your-client-id>
OAUTH_CLIENT_SECRET=<your-secret>

# Google Chat Webhooks
GCHAT_WEBHOOK_MONITORING=https://chat.googleapis.com/...
GCHAT_WEBHOOK_SECURITY=https://chat.googleapis.com/...

# Service Integration
SONARQUBE_TOKEN=<token>
```

### Adding New Scrape Targets

Edit `monitoring/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'my-service'
    static_configs:
      - targets: ['my-service:port']
```

### Creating Custom Alerts

Add to `monitoring/prometheus/alerts/custom.yml`:

```yaml
groups:
  - name: custom_alerts
    rules:
      - alert: MyCustomAlert
        expr: my_metric > threshold
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Custom alert triggered"
```

## Backup and Recovery

### Automated Backup

```bash
# Run backup
make monitoring-backup

# Schedule daily backup
0 2 * * * /path/to/gitea/scripts/backup-grafana.sh
```

### Manual Recovery

```bash
# List backups
ls -la /backup/grafana/

# Restore from backup
tar xzf /backup/grafana/grafana-backup-20240101.tar.gz
docker exec grafana-postgres psql -U grafana < grafana.sql
```

## Troubleshooting

### Common Issues

#### Services Not Starting
```bash
# Check logs
docker-compose -f monitoring/docker-compose-monitoring.yml logs

# Verify port availability
netstat -tuln | grep -E '9090|3000|9093'
```

#### Prometheus Not Scraping
```bash
# Check targets
curl http://localhost:9090/api/v1/targets

# Verify connectivity
docker exec prometheus curl -v http://target:port/metrics
```

#### Grafana Database Issues
```bash
# Check PostgreSQL
docker logs grafana-postgres
docker exec grafana-postgres psql -U grafana -c "SELECT 1"
```

## Security Considerations

### Production Deployment

1. **Enable TLS/HTTPS** for all endpoints
2. **Configure OAuth2** authentication with GCP
3. **Set strong passwords** for all service accounts
4. **Implement network segmentation** and firewall rules
5. **Enable audit logging** for all components
6. **Regular security scanning** of container images
7. **Implement RBAC** for multi-team access

### Hardening Checklist

- [ ] Change default passwords
- [ ] Enable TLS/HTTPS
- [ ] Configure OAuth2/SSO
- [ ] Set up firewall rules
- [ ] Enable audit logging
- [ ] Configure backup encryption
- [ ] Implement network policies
- [ ] Regular security updates

## Evidence Collection

### Compliance Evidence

Evidence is automatically collected in:
```
compliance/evidence/monitoring/
├── setup-<timestamp>.json
├── backup-<timestamp>.json
├── alerts-<timestamp>.json
└── reports/
    └── monitoring-report-<timestamp>.txt
```

### Generate Evidence

```bash
# Manual evidence collection
make monitoring-compliance

# Query specific metrics
curl -s 'http://localhost:9090/api/v1/query?query=compliance_control_implemented{framework="cmmc"}'
```

## Support

### Documentation

- [Deployment Guide](../docs/MONITORING_DEPLOYMENT_GUIDE.md)
- [Dashboard Guide](../docs/GRAFANA_DASHBOARD_GUIDE.md)
- [Alerting Runbook](../docs/ALERTING_RUNBOOK.md)

### Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [CMMC Assessment Guide](https://www.acq.osd.mil/cmmc/)
- [NIST SP 800-171](https://csrc.nist.gov/publications/detail/sp/800-171/rev-2/final)

### Contact

For issues or questions:
- Create an issue in the repository
- Contact the DevSecOps team
- Check logs: `docker-compose logs -f [service]`

## License

This monitoring stack implementation is part of the Gitea DevSecOps platform and follows the same licensing terms.