# Alerting Runbook

## CMMC 2.0 and NIST Compliance
- **CMMC 2.0**: IR.L2-3.6.1, IR.L2-3.6.2 - Incident Response
- **NIST SP 800-171**: 3.6.1, 3.6.2 - Incident Response
- **NIST SP 800-53**: IR-4, IR-5, IR-6 - Incident Handling

## Alert Response Procedures

### Critical Security Alerts

#### CriticalVulnerabilityDetected

**Severity**: CRITICAL
**SLA**: 15 minutes initial response, 4 hours to contain

**Symptoms**:
- Critical vulnerability (CVSS 9.0+) detected in production systems
- Alert fired to #security-alerts channel

**Response Steps**:
1. **Acknowledge** (Within 15 minutes):
   ```bash
   # Acknowledge in alertmanager
   curl -X POST http://localhost:9093/api/v1/silences \
     -H "Content-Type: application/json" \
     -d '{"matchers":[{"name":"alertname","value":"CriticalVulnerabilityDetected"}],"startsAt":"now","endsAt":"1h","comment":"Acknowledged - investigating"}'
   ```

2. **Identify Affected Systems**:
   ```bash
   # Query Prometheus for details
   curl -s http://localhost:9090/api/v1/query?query='security_scan_vulnerability_count{severity="CRITICAL"} > 0'

   # Check security dashboard
   open https://grafana.example.com/d/security/security-scanning-metrics
   ```

3. **Assess Impact**:
   - Check if vulnerability is exploitable
   - Identify exposed attack surface
   - Review access logs for exploitation attempts

4. **Containment**:
   ```bash
   # Isolate affected container
   docker pause <container_name>

   # Or stop service
   docker-compose stop <service_name>

   # Apply network isolation
   iptables -I DOCKER-USER -s <container_ip> -j DROP
   ```

5. **Remediation**:
   ```bash
   # Update vulnerable package
   docker pull <image>:latest
   docker-compose up -d <service>

   # Verify fix
   docker exec <container> trivy image --severity CRITICAL <image>
   ```

6. **Evidence Collection**:
   ```bash
   # Collect evidence
   mkdir -p /evidence/$(date +%Y%m%d)
   docker logs <container> > /evidence/$(date +%Y%m%d)/container.log
   docker inspect <container> > /evidence/$(date +%Y%m%d)/container_inspect.json

   # Generate hash
   sha256sum /evidence/$(date +%Y%m%d)/* > /evidence/$(date +%Y%m%d)/evidence.sha256
   ```

7. **Post-Incident**:
   - Document in incident tracking system
   - Update vulnerability database
   - Schedule post-mortem meeting

#### MalwareDetected

**Severity**: CRITICAL
**SLA**: Immediate response, 1 hour to contain

**Response Steps**:
1. **Immediate Isolation**:
   ```bash
   # Stop affected container immediately
   docker kill <container_name>

   # Quarantine the container filesystem
   docker commit <container_name> quarantine/malware-$(date +%Y%m%d)
   ```

2. **Preserve Evidence**:
   ```bash
   # Export container filesystem
   docker export <container_name> > /evidence/malware-container-$(date +%Y%m%d).tar

   # Capture memory dump if possible
   docker exec <container_name> gcore -o /tmp/coredump <pid>
   ```

3. **Analysis**:
   ```bash
   # Scan with multiple engines
   clamscan /evidence/malware-container-*.tar

   # Check for persistence mechanisms
   docker run --rm -v /evidence:/scan aquasec/trivy fs /scan
   ```

4. **Eradication**:
   ```bash
   # Remove infected container and images
   docker rm -f <container_name>
   docker rmi <infected_image>

   # Clean up volumes
   docker volume prune -f
   ```

5. **Recovery**:
   ```bash
   # Rebuild from clean image
   docker build --no-cache -t <image> .

   # Deploy with enhanced monitoring
   docker run -d --security-opt="no-new-privileges:true" --read-only <image>
   ```

### Compliance Alerts

#### EvidenceCollectionFailure

**Severity**: CRITICAL
**SLA**: 30 minutes to investigate, 2 hours to resolve

**Response Steps**:
1. **Check Evidence Collection Service**:
   ```bash
   # Check exporter status
   docker logs compliance_exporter

   # Verify evidence directory
   ls -la /compliance/evidence/
   ```

2. **Manual Evidence Collection**:
   ```bash
   # Run manual collection
   docker exec compliance_exporter python -c "
   from compliance_exporter import ComplianceExporter
   exporter = ComplianceExporter()
   exporter.check_control_implementation()
   "
   ```

3. **Fix Issues**:
   ```bash
   # Fix permissions
   chmod -R 755 /compliance/evidence/
   chown -R exporter:exporter /compliance/evidence/

   # Restart service
   docker-compose restart compliance_exporter
   ```

#### AuditLogRetentionViolation

**Severity**: CRITICAL
**SLA**: 1 hour to resolve

**Response Steps**:
1. **Check Current Retention**:
   ```bash
   # Check Prometheus retention
   curl http://localhost:9090/api/v1/status/config | jq '.data.yaml' | grep retention

   # Check disk space
   df -h /monitoring/data/prometheus
   ```

2. **Adjust Retention**:
   ```bash
   # Update docker-compose.yml
   sed -i 's/--storage.tsdb.retention.time=.*/--storage.tsdb.retention.time=90d/' \
     monitoring/docker-compose-monitoring.yml

   # Restart Prometheus
   docker-compose restart prometheus
   ```

3. **Archive Old Data**:
   ```bash
   # Archive to cold storage
   tar czf /backup/prometheus-archive-$(date +%Y%m).tar.gz \
     /monitoring/data/prometheus/

   # Upload to GCS
   gsutil cp /backup/prometheus-archive-*.tar.gz gs://compliance-archives/
   ```

### Operational Alerts

#### ServiceDown

**Severity**: CRITICAL
**SLA**: 5 minutes to acknowledge, 30 minutes to restore

**Response Steps**:
1. **Initial Check**:
   ```bash
   # Check service status
   docker-compose ps

   # Check logs
   docker-compose logs --tail=100 <service_name>
   ```

2. **Quick Recovery Attempt**:
   ```bash
   # Restart service
   docker-compose restart <service_name>

   # If that fails, recreate
   docker-compose up -d --force-recreate <service_name>
   ```

3. **Root Cause Analysis**:
   ```bash
   # Check resource usage
   docker stats --no-stream

   # Check system resources
   free -h
   df -h

   # Check for OOM kills
   dmesg | grep -i "killed process"
   ```

4. **Escalation** (if not resolved in 30 minutes):
   - Page on-call engineer
   - Prepare for failover if available
   - Notify stakeholders

#### DiskSpaceCritical

**Severity**: CRITICAL
**SLA**: 15 minutes to free space

**Response Steps**:
1. **Immediate Actions**:
   ```bash
   # Check disk usage
   df -h
   du -sh /var/lib/docker/*

   # Clean Docker resources
   docker system prune -af --volumes

   # Clean old logs
   find /var/log -type f -name "*.log" -mtime +7 -delete
   ```

2. **Prometheus Data Cleanup**:
   ```bash
   # Delete old blocks
   curl -X POST http://localhost:9090/api/v1/admin/tsdb/delete_series \
     -d 'match[]={__name__=~"test.*"}'

   # Clean tombstones
   curl -X POST http://localhost:9090/api/v1/admin/tsdb/clean_tombstones
   ```

3. **Long-term Solution**:
   ```bash
   # Add disk space monitoring
   # Implement data retention policies
   # Set up automated cleanup jobs
   ```

### Performance Alerts

#### HighCPUUsage

**Severity**: WARNING
**SLA**: 1 hour to investigate

**Response Steps**:
1. **Identify Process**:
   ```bash
   # Top processes by CPU
   docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

   # Inside container
   docker exec <container> top -b -n 1
   ```

2. **Optimization**:
   ```bash
   # Adjust resource limits
   docker update --cpus="2.0" <container>

   # Scale horizontally if possible
   docker-compose up -d --scale <service>=3
   ```

#### HighMemoryUsage

**Severity**: WARNING
**SLA**: 1 hour to investigate

**Response Steps**:
1. **Memory Analysis**:
   ```bash
   # Check memory usage
   docker exec <container> cat /proc/meminfo

   # Java heap dump (if applicable)
   docker exec <container> jmap -dump:format=b,file=/tmp/heapdump.hprof <pid>
   ```

2. **Remediation**:
   ```bash
   # Increase memory limit
   docker update --memory="4g" --memory-swap="4g" <container>

   # Restart to apply
   docker-compose restart <service>
   ```

## Alert Routing and Escalation

### Escalation Matrix

| Alert Category | L1 Response | L2 Escalation | L3 Escalation | Executive |
|---------------|-------------|---------------|---------------|-----------|
| Security Critical | 15 min | 30 min | 1 hour | 2 hours |
| Compliance Critical | 30 min | 1 hour | 2 hours | 4 hours |
| Operational Critical | 15 min | 45 min | 2 hours | 4 hours |
| Warning | 2 hours | 4 hours | Next business day | Weekly report |

### On-Call Rotation

```yaml
# PagerDuty integration
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - routing_key: '<integration-key>'
        severity: 'critical'
        client: 'Prometheus'
        client_url: 'https://prometheus.example.com'
```

### Communication Templates

#### Initial Response
```
ALERT: [Alert Name]
Severity: [CRITICAL/WARNING]
Time: [Timestamp]
Affected: [Component/Service]
Status: Acknowledged, investigating
ETA: [Expected resolution time]
```

#### Status Update
```
UPDATE: [Alert Name]
Current Status: [Investigating/Mitigating/Resolved]
Actions Taken: [List of actions]
Next Steps: [Planned actions]
ETA: [Updated resolution time]
```

#### Resolution
```
RESOLVED: [Alert Name]
Resolution Time: [Duration]
Root Cause: [Brief description]
Fix Applied: [What was done]
Prevention: [Future prevention measures]
Post-Mortem: [Link to document]
```

## Alert Testing

### Monthly Alert Test

```bash
#!/bin/bash
# Test all critical alerts

# Test security alert
curl -X POST http://localhost:9090/api/v1/admin/tsdb/delete_series \
  -d 'match[]={alertname="TestSecurityAlert"}'

# Test compliance alert
amtool alert add TestComplianceAlert \
  severity=critical \
  category=compliance \
  --alertmanager.url=http://localhost:9093

# Test operational alert
docker stop test-container || true

# Verify alerts fired
sleep 60
curl http://localhost:9093/api/v1/alerts | jq '.[] | select(.labels.severity=="critical")'
```

### Alert Rule Validation

```bash
# Validate Prometheus rules
docker exec prometheus promtool check rules /etc/prometheus/alerts/*.yml

# Test rule evaluation
docker exec prometheus promtool test rules tests/alert_tests.yml
```

## Metrics and KPIs

### Alert Metrics

Monitor these metrics for alert health:

```promql
# Alert firing rate
rate(prometheus_notifications_sent_total[1h])

# Alert resolution time
histogram_quantile(0.95, rate(alert_resolution_duration_seconds_bucket[24h]))

# False positive rate
(count(alerts_silenced_as_false_positive) / count(ALERTS)) * 100

# MTTR by severity
avg by (severity) (alert_resolution_time_minutes)
```

### Monthly Report

Generate monthly alert report:

```bash
#!/bin/bash
# Monthly alert report

echo "=== Monthly Alert Report ==="
echo "Date: $(date)"
echo ""

# Total alerts
echo "Total Alerts Fired:"
curl -s "http://localhost:9090/api/v1/query?query=increase(ALERTS[30d])" | \
  jq '.data.result[0].value[1]'

# By severity
echo "By Severity:"
curl -s "http://localhost:9090/api/v1/query?query=count by (severity) (ALERTS)" | \
  jq '.data.result[] | "\(.metric.severity): \(.value[1])"'

# MTTR
echo "Mean Time to Resolve:"
curl -s "http://localhost:9090/api/v1/query?query=avg(alert_resolution_time_minutes)" | \
  jq '.data.result[0].value[1]'
```

## Appendix

### Important Commands

```bash
# Silence alert
amtool silence add alertname="ServiceDown" --duration="2h" --comment="Maintenance"

# List silences
amtool silence query

# Expire silence
amtool silence expire <silence_id>

# Check alert status
amtool alert query

# Get alerting rules
curl http://localhost:9090/api/v1/rules?type=alert

# Get active alerts
curl http://localhost:9090/api/v1/alerts
```

### References

- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/overview/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [NIST Incident Response Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-61r2.pdf)
- [CMMC Assessment Guide](https://www.acq.osd.mil/cmmc/docs/AG_Level2_V2.0.pdf)