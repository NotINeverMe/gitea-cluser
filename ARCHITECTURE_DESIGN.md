# DevSecOps Platform Architecture & Authorization Boundary

## AUTHORIZATION BOUNDARY DIAGRAM (ABD)

```mermaid
graph TB
    subgraph "INTERNET ZONE - Untrusted"
        DEV[Developer Workstations]
        EXT[External APIs]
        PUB[Public Registries]
    end

    subgraph "DMZ - Semi-Trusted"
        WAF[Web Application Firewall]
        LB[Load Balancer]
        PROXY[Reverse Proxy]
    end

    subgraph "BUILD ZONE - Controlled"
        subgraph "Gitea Infrastructure"
            GIT[Gitea Server Cluster]
            RUN[CI/CD Runners]
            REG[Container Registry]
        end

        subgraph "Security Stack"
            SONAR[SonarQube]
            TRIVY[Trivy Scanner]
            GRYPE[Grype Scanner]
            ZAP[OWASP ZAP]
        end

        subgraph "IaC Security"
            CHECK[Checkov]
            TFSEC[tfsec]
            TERRA[Terrascan]
            COST[Infracost]
        end
    end

    subgraph "PRODUCTION ZONE - Trusted"
        subgraph "Monitoring"
            PROM[Prometheus]
            GRAF[Grafana]
            ALERT[AlertManager]
        end

        subgraph "GitOps"
            ATL[Atlantis]
            TGRUNT[Terragrunt]
            N8N[n8n Workflows]
        end

        subgraph "GCP Integration"
            SCC[Security Command Center]
            ASSET[Asset Inventory]
            LOG[Cloud Logging]
            KMS[Cloud KMS]
        end
    end

    subgraph "COMPLIANCE ZONE - Restricted"
        AUDIT[Audit Logs]
        EVID[Evidence Store]
        SSP[SSP Documentation]
        CTRL[Control Matrix]
    end

    %% Data Flows with Security Annotations
    DEV -->|TLS 1.3/mTLS| WAF
    WAF -->|Auth: OIDC/SAML| LB
    LB -->|Rate Limited| PROXY
    PROXY -->|JWT Tokens| GIT

    GIT -->|Webhook| RUN
    RUN -->|Signed Images| REG
    RUN -->|SAST| SONAR
    RUN -->|Container Scan| TRIVY
    RUN -->|CVE Check| GRYPE
    RUN -->|DAST| ZAP

    RUN -->|IaC Scan| CHECK
    RUN -->|TF Security| TFSEC
    RUN -->|Policy Check| TERRA
    RUN -->|Cost Analysis| COST

    REG -->|Deploy| ATL
    ATL -->|State Mgmt| TGRUNT
    ATL -->|Provision| SCC

    GIT -->|Metrics| PROM
    PROM -->|Visualize| GRAF
    GRAF -->|Alerts| ALERT
    ALERT -->|Automate| N8N

    N8N -->|Collect| ASSET
    ASSET -->|Archive| LOG
    LOG -->|Encrypt| KMS
    KMS -->|Store| EVID

    EVID -->|Generate| SSP
    SSP -->|Map| CTRL
    CTRL -->|Report| AUDIT
```

## DATA FLOW DIAGRAM (DFD)

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as Gitea
    participant CI as CI/CD Pipeline
    participant Sec as Security Gates
    participant IaC as IaC Validation
    participant Reg as Container Registry
    participant GCP as GCP Resources
    participant Mon as Monitoring
    participant Comp as Compliance

    Dev->>Git: Push Code (TLS 1.3)
    Git->>CI: Trigger Pipeline (Webhook)

    CI->>Sec: Run Security Scans
    activate Sec
    Sec-->>Sec: SAST (SonarQube)
    Sec-->>Sec: Container Scan (Trivy/Grype)
    Sec-->>Sec: DAST (OWASP ZAP)
    Sec-->>CI: Security Report
    deactivate Sec

    CI->>IaC: Validate Infrastructure
    activate IaC
    IaC-->>IaC: Checkov Scan
    IaC-->>IaC: tfsec Analysis
    IaC-->>IaC: Terrascan Policy
    IaC-->>IaC: Infracost Estimate
    IaC-->>CI: Validation Results
    deactivate IaC

    alt Security & IaC Pass
        CI->>Reg: Push Signed Image
        Reg->>GCP: Deploy Resources
        GCP->>Mon: Send Metrics
        Mon->>Comp: Generate Evidence
        Comp-->>Dev: Success Notification
    else Security or IaC Fail
        CI-->>Dev: Failure Report
        CI->>Mon: Log Failure
        Mon->>Comp: Document Issue
    end
```

## NETWORK SEGMENTATION & TRUST ZONES

### Zone Definitions

| Zone | Trust Level | Access Controls | Data Classification |
|------|-------------|-----------------|-------------------|
| Internet | Untrusted | WAF, DDoS Protection | Public |
| DMZ | Semi-Trusted | Rate Limiting, IP Whitelisting | Public/Internal |
| Build | Controlled | RBAC, Service Accounts | Internal/Confidential |
| Production | Trusted | mTLS, Zero Trust | Confidential/Secret |
| Compliance | Restricted | MFA, Audit Logging | Secret/Regulatory |

### Security Controls by Zone

#### Internet Zone
- **Ingress**: CloudFlare/Akamai DDoS protection
- **Authentication**: None (public access)
- **Encryption**: TLS 1.3 minimum
- **Monitoring**: Traffic analysis, anomaly detection

#### DMZ Zone
- **Ingress**: Web Application Firewall (ModSecurity)
- **Authentication**: Basic auth for admin interfaces
- **Encryption**: TLS termination and re-encryption
- **Monitoring**: Request logging, rate monitoring

#### Build Zone
- **Ingress**: Authenticated webhooks only
- **Authentication**: OIDC/SAML SSO required
- **Encryption**: mTLS between services
- **Monitoring**: Pipeline metrics, security events

#### Production Zone
- **Ingress**: Service mesh (Istio) controlled
- **Authentication**: Service account tokens
- **Encryption**: In-transit and at-rest (AES-256)
- **Monitoring**: Full observability stack

#### Compliance Zone
- **Ingress**: Jump host required
- **Authentication**: MFA + privileged access management
- **Encryption**: Hardware security module (HSM) backed
- **Monitoring**: Complete audit trail, tamper detection

## TOOL INTEGRATION ARCHITECTURE

### Security Tool Pipeline

```yaml
pipeline:
  stages:
    - name: Source
      tools:
        - gitea: Repository management
        - git-secrets: Credential scanning

    - name: Build
      tools:
        - sonarqube: Static analysis
        - semgrep: Pattern matching
        - bandit: Python security

    - name: Package
      tools:
        - trivy: Container scanning
        - grype: Vulnerability detection
        - cosign: Image signing

    - name: Deploy
      tools:
        - checkov: IaC scanning
        - tfsec: Terraform security
        - terrascan: Policy as code

    - name: Runtime
      tools:
        - falco: Runtime security
        - osquery: Endpoint monitoring
        - wazuh: HIDS/SIEM
```

### Monitoring Stack Architecture

```yaml
monitoring:
  collection:
    - prometheus: Metrics aggregation
    - node_exporter: System metrics
    - cadvisor: Container metrics
    - blackbox_exporter: Endpoint monitoring

  storage:
    - victoria_metrics: Long-term storage
    - loki: Log aggregation
    - tempo: Distributed tracing

  visualization:
    - grafana: Dashboards
    - alertmanager: Alert routing
    - karma: Alert dashboard

  automation:
    - n8n: Workflow orchestration
    - ansible: Remediation playbooks
```

## GCP INTEGRATION POINTS

### Service Integrations

| GCP Service | Integration Purpose | Security Controls |
|-------------|-------------------|-------------------|
| Cloud IAM | Identity federation | Workload identity, least privilege |
| Cloud KMS | Encryption keys | HSM-backed, rotation policy |
| Cloud Storage | Artifact storage | Signed URLs, retention policies |
| Cloud Build | Native CI/CD | Private pools, VPC-SC |
| Cloud Run | Serverless compute | Binary authorization, min TLS |
| Security Command Center | Vulnerability management | Real-time findings, compliance |
| Cloud Asset Inventory | Resource tracking | Change detection, exports |
| Cloud Logging | Centralized logs | Log sinks, BigQuery analysis |
| Cloud Armor | DDoS protection | Rate limiting, geo-blocking |
| VPC Service Controls | Network security | Perimeter protection, access levels |

### Data Flow Security

```mermaid
graph LR
    subgraph "Encryption at Rest"
        KMS[Cloud KMS]
        CMEK[Customer Managed Keys]
        HSM[Hardware Security Module]
    end

    subgraph "Encryption in Transit"
        TLS[TLS 1.3]
        MTLS[Mutual TLS]
        VPN[Cloud VPN]
    end

    subgraph "Access Controls"
        IAM[Cloud IAM]
        WI[Workload Identity]
        PAP[Privileged Access]
    end

    KMS --> CMEK
    CMEK --> HSM
    TLS --> MTLS
    MTLS --> VPN
    IAM --> WI
    WI --> PAP
```

## DISASTER RECOVERY ARCHITECTURE

### Backup Strategy

```yaml
backup:
  gitea:
    frequency: Every 6 hours
    retention: 30 days
    location: Multi-region Cloud Storage
    encryption: CMEK with Cloud KMS

  databases:
    frequency: Daily full, hourly incremental
    retention: 90 days
    location: Cross-region replicated
    encryption: AES-256-GCM

  configurations:
    frequency: On change
    retention: Unlimited
    location: Version controlled in Git
    encryption: GPG signed commits

  secrets:
    frequency: On rotation
    retention: 3 versions
    location: Secret Manager
    encryption: Envelope encryption
```

### Recovery Objectives

| Component | RTO | RPO | Backup Method | Recovery Method |
|-----------|-----|-----|---------------|-----------------|
| Gitea | 1 hour | 6 hours | Snapshot + WAL | Restore from snapshot |
| CI/CD | 30 minutes | 1 hour | Config as code | Redeploy from Git |
| Security Tools | 2 hours | 24 hours | Container images | Pull and redeploy |
| Monitoring | 4 hours | 1 hour | Persistent volumes | Volume restore |
| Compliance Data | 15 minutes | 5 minutes | Real-time replication | Failover to replica |