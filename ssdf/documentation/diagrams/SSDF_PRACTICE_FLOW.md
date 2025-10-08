# SSDF Practice Flow Diagram

## Overview
This diagram maps all 47 NIST SSDF practices across four quadrants (Prepare Organization, Protect Software, Produce Well-Secured Software, Respond to Vulnerabilities), showing practice dependencies, evidence flows, tool integration points, and feedback loops.

## Mermaid Diagram

```mermaid
graph TB
    subgraph PO["PREPARE ORGANIZATION (PO) - 12 Practices"]
        direction TB
        PO1["PO.1: Define Secure<br/>Development Practices<br/>📋 Security policies<br/>🔧 git-secrets, pre-commit"]
        PO2["PO.2: Implement Secure<br/>Development Training<br/>📋 Training records<br/>🔧 Security Champions"]
        PO3["PO.3: Create Security<br/>Requirements<br/>📋 Requirements docs<br/>🔧 Threat models"]
        PO4["PO.4: Define Secure<br/>Development Metrics<br/>📋 KPI dashboard<br/>🔧 Prometheus, Grafana"]
        PO5["PO.5: Implement Secure<br/>Supply Chain<br/>📋 SBOM, Signatures<br/>🔧 Syft, Cosign, SLSA"]

        PO1 --> PO2
        PO2 --> PO3
        PO3 --> PO4
        PO1 --> PO5
    end

    subgraph PS["PROTECT SOFTWARE (PS) - 7 Practices"]
        direction TB
        PS1["PS.1: Store Code in<br/>Version Control<br/>📋 Git commit logs<br/>🔧 Gitea, signed commits"]
        PS2["PS.2: Access Control<br/>for Code Repositories<br/>📋 Access audit logs<br/>🔧 RBAC, IAM policies"]
        PS3["PS.3: Protect Software<br/>Artifacts<br/>📋 Artifact signatures<br/>🔧 Cosign, KMS, OCI registry"]

        PS1 --> PS2
        PS2 --> PS3
    end

    subgraph PW["PRODUCE WELL-SECURED SOFTWARE (PW) - 19 Practices"]
        direction TB

        subgraph PWDesign["Design Phase"]
            PW1["PW.1: Use Secure<br/>Design Principles<br/>📋 Architecture docs<br/>🔧 Threat modeling"]
            PW2["PW.2: Review Code<br/>📋 Review records<br/>🔧 SonarQube, PR reviews"]
        end

        subgraph PWCode["Development Phase"]
            PW4["PW.4: Reuse Existing<br/>Software<br/>📋 Dependency list<br/>🔧 SBOM, license check"]
            PW5["PW.5: Create Well-Secured<br/>Software<br/>📋 Coding standards<br/>🔧 Linters, formatters"]
            PW6["PW.6: Configure Tools<br/>📋 Tool configs<br/>🔧 SAST, DAST, scanners"]
        end

        subgraph PWTest["Testing Phase"]
            PW7["PW.7: Test for<br/>Vulnerabilities<br/>📋 Scan reports<br/>🔧 Trivy, Grype, ZAP"]
            PW8["PW.8: Prepare for<br/>Deployment<br/>📋 Deploy manifests<br/>🔧 Atlantis, Helm"]
            PW9["PW.9: Verify Software<br/>Integrity<br/>📋 Signatures, hashes<br/>🔧 Cosign, in-toto"]
        end

        PW1 --> PW2
        PW2 --> PW4
        PW4 --> PW5
        PW5 --> PW6
        PW6 --> PW7
        PW7 --> PW8
        PW8 --> PW9
    end

    subgraph RV["RESPOND TO VULNERABILITIES (RV) - 9 Practices"]
        direction TB
        RV1["RV.1: Identify<br/>Vulnerabilities<br/>📋 CVE reports<br/>🔧 Trivy, Grype, OSV"]
        RV2["RV.2: Assess and<br/>Triage Vulns<br/>📋 Risk assessments<br/>🔧 Dependency Track"]
        RV3["RV.3: Remediate<br/>Vulnerabilities<br/>📋 Patch records<br/>🔧 Automated patching"]

        RV1 --> RV2
        RV2 --> RV3
        RV3 -.-> PW7
    end

    %% Cross-quadrant dependencies
    PO1 --> PS1
    PO3 --> PW1
    PO5 --> PS3
    PS1 --> PW2
    PS3 --> PW9
    PW7 --> RV1
    PW9 --> RV1

    %% Evidence flows
    PO4 -.Evidence.-> Dashboard[(Evidence<br/>Dashboard)]
    PS3 -.Evidence.-> Dashboard
    PW9 -.Evidence.-> Dashboard
    RV2 -.Evidence.-> Dashboard

    %% Tool integration
    Tools[("34 Security<br/>Tools<br/>Integration")]
    Tools -.-> PW6
    Tools -.-> PW7
    Tools -.-> RV1

    %% Feedback loops
    RV3 -.Feedback.-> PO2
    RV2 -.Feedback.-> PO4
    PW7 -.Feedback.-> PW5

    %% Styling
    classDef po fill:#e3f2fd,stroke:#1976d2,stroke-width:3px
    classDef ps fill:#f3e5f5,stroke:#7b1fa2,stroke-width:3px
    classDef pw fill:#fff3e0,stroke:#f57c00,stroke-width:3px
    classDef rv fill:#ffebee,stroke:#c62828,stroke-width:3px
    classDef evidence fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    classDef tools fill:#fce4ec,stroke:#c2185b,stroke-width:2px

    class PO1,PO2,PO3,PO4,PO5 po
    class PS1,PS2,PS3 ps
    class PW1,PW2,PW4,PW5,PW6,PW7,PW8,PW9 pw
    class RV1,RV2,RV3 rv
    class Dashboard evidence
    class Tools tools
```

## PlantUML Four-Quadrant Diagram

```plantuml
@startuml SSDF_Practice_Flow
!theme plain
scale 1.5

skinparam defaultTextAlignment center
skinparam backgroundColor #FFFFFF
skinparam shadowing false
skinparam packageStyle rectangle

' Define colors
skinparam package {
  BackgroundColor<<po>> #E3F2FD
  BorderColor<<po>> #1976D2
  BackgroundColor<<ps>> #F3E5F5
  BorderColor<<ps>> #7B1FA2
  BackgroundColor<<pw>> #FFF3E0
  BorderColor<<pw>> #F57C00
  BackgroundColor<<rv>> #FFEBEE
  BorderColor<<rv>> #C62828
}

title SSDF Practice Flow - Four Quadrants\nNIST SP 800-218 Framework

package "PREPARE ORGANIZATION (PO)\n12 Practices" <<po>> {
  [PO.1\nDefine Secure\nDevelopment Practices\n\n🔧 git-secrets\n🔧 pre-commit\n🔧 Policy docs] as PO1

  [PO.2\nImplement Secure\nDevelopment Training\n\n🔧 Security training\n🔧 Champion program\n🔧 Awareness] as PO2

  [PO.3\nCreate Security\nRequirements\n\n🔧 Threat models\n🔧 Security specs\n🔧 Risk analysis] as PO3

  [PO.4\nDefine Metrics\nand KPIs\n\n🔧 Prometheus\n🔧 Grafana\n🔧 Dashboard] as PO4

  [PO.5\nSecure Supply\nChain\n\n🔧 SBOM (Syft)\n🔧 Signatures (Cosign)\n🔧 SLSA provenance] as PO5

  PO1 -down-> PO2
  PO2 -down-> PO3
  PO3 -down-> PO4
  PO1 -right-> PO5
}

package "PROTECT SOFTWARE (PS)\n7 Practices" <<ps>> {
  [PS.1\nVersion Control\nfor All Code\n\n🔧 Gitea\n🔧 Signed commits\n🔧 Branch protection] as PS1

  [PS.2\nAccess Control\nfor Repositories\n\n🔧 RBAC\n🔧 IAM policies\n🔧 Audit logs] as PS2

  [PS.3\nProtect Software\nArtifacts\n\n🔧 OCI registry\n🔧 Cosign signing\n🔧 KMS encryption] as PS3

  PS1 -down-> PS2
  PS2 -down-> PS3
}

package "PRODUCE WELL-SECURED SOFTWARE (PW)\n19 Practices" <<pw>> {
  rectangle "Design Phase" {
    [PW.1\nSecure Design\nPrinciples\n\n🔧 Architecture review\n🔧 Threat modeling\n🔧 Security patterns] as PW1

    [PW.2\nReview Code\n\n🔧 SonarQube SAST\n🔧 PR reviews\n🔧 Peer approval] as PW2
  }

  rectangle "Development Phase" {
    [PW.4\nReuse Existing\nSoftware\n\n🔧 Dependency mgmt\n🔧 License check\n🔧 SBOM tracking] as PW4

    [PW.5\nCreate Well-Secured\nSoftware\n\n🔧 Secure coding\n🔧 Linters\n🔧 Standards] as PW5

    [PW.6\nConfigure Security\nTools\n\n🔧 SAST\n🔧 DAST\n🔧 SCA] as PW6
  }

  rectangle "Testing Phase" {
    [PW.7\nTest for\nVulnerabilities\n\n🔧 Trivy\n🔧 Grype\n🔧 OWASP ZAP] as PW7

    [PW.8\nPrepare for\nDeployment\n\n🔧 Atlantis\n🔧 Helm charts\n🔧 K8s manifests] as PW8

    [PW.9\nVerify Software\nIntegrity\n\n🔧 Cosign\n🔧 in-toto\n🔧 SLSA] as PW9
  }

  PW1 -down-> PW2
  PW2 -down-> PW4
  PW4 -right-> PW5
  PW5 -right-> PW6
  PW6 -down-> PW7
  PW7 -right-> PW8
  PW8 -right-> PW9
}

package "RESPOND TO VULNERABILITIES (RV)\n9 Practices" <<rv>> {
  [RV.1\nIdentify\nVulnerabilities\n\n🔧 Trivy\n🔧 Grype\n🔧 OSV-Scanner] as RV1

  [RV.2\nAssess and Triage\nVulnerabilities\n\n🔧 Dependency Track\n🔧 Risk scoring\n🔧 CVSS analysis] as RV2

  [RV.3\nRemediate\nVulnerabilities\n\n🔧 Patch management\n🔧 Auto-updates\n🔧 Hotfixes] as RV3

  RV1 -down-> RV2
  RV2 -down-> RV3
}

' Cross-quadrant dependencies
PO1 -[#1976D2,thickness=2]-> PS1 : "Policies\nto Code"
PO3 -[#1976D2,thickness=2]-> PW1 : "Requirements\nto Design"
PO5 -[#1976D2,thickness=2]-> PS3 : "Supply Chain\nControls"

PS1 -[#7B1FA2,thickness=2]-> PW2 : "Code to\nReview"
PS3 -[#7B1FA2,thickness=2]-> PW9 : "Artifact\nProtection"

PW7 -[#F57C00,thickness=2]-> RV1 : "Test Results\nto Vuln ID"
PW9 -[#F57C00,thickness=2]-> RV1 : "Integrity\nChecks"

' Feedback loops
RV3 -[#C62828,dashed,thickness=2]-> PO2 : "Lessons\nLearned"
RV2 -[#C62828,dashed,thickness=2]-> PO4 : "Metrics\nUpdate"
PW7 -[#F57C00,dashed,thickness=2]-> PW5 : "Code\nImprovements"

' Evidence collection
database "Evidence\nDashboard\n\n📊 GCS Storage\n📊 PostgreSQL\n📊 n8n Workflow" as Evidence

PO4 -[#388E3C,dotted]-> Evidence : "Metrics"
PS3 -[#388E3C,dotted]-> Evidence : "Artifacts"
PW9 -[#388E3C,dotted]-> Evidence : "Attestations"
RV2 -[#388E3C,dotted]-> Evidence : "Vuln Reports"

' Tool integration hub
cloud "34 Security Tools\n\n🔧 SAST/DAST\n🔧 SCA\n🔧 Container\n🔧 IaC\n🔧 Runtime" as Tools

Tools -[#C2185B,dotted]-> PW6 : "Tool\nConfig"
Tools -[#C2185B,dotted]-> PW7 : "Testing"
Tools -[#C2185B,dotted]-> RV1 : "Detection"

legend bottom
  |= Symbol |= Meaning |
  | Solid Arrow | Direct dependency |
  | Dashed Arrow | Feedback loop |
  | Dotted Arrow | Evidence/Tool flow |
  | 🔧 | Tool or implementation |
  | 📊 | Data/Evidence artifact |
endlegend

@enduml
```

## ASCII Four-Quadrant Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    SSDF PRACTICE FLOW                                           │
│                           NIST SP 800-218 - Four Quadrants                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────┬───────────────────────────────────────────────────┐
│  QUADRANT 1: PREPARE ORGANIZATION (PO)      │  QUADRANT 2: PROTECT SOFTWARE (PS)               │
│  12 Practices - Foundation & Governance     │  7 Practices - Repository & Artifact Security    │
├─────────────────────────────────────────────┼───────────────────────────────────────────────────┤
│                                             │                                                   │
│  ┌────────────────────────────────────┐    │    ┌────────────────────────────────────┐        │
│  │ PO.1: Define Secure Development    │    │    │ PS.1: Version Control for Code     │        │
│  │       Practices                    │────┼───▶│       - Gitea repository           │        │
│  │ 🔧 git-secrets, pre-commit         │    │    │       - Signed commits             │        │
│  │ 📋 Security policies               │    │    │       - Branch protection          │        │
│  └────────────┬───────────────────────┘    │    └─────────────┬──────────────────────┘        │
│               │                             │                  │                                │
│               ▼                             │                  ▼                                │
│  ┌────────────────────────────────────┐    │    ┌────────────────────────────────────┐        │
│  │ PO.2: Implement Security Training  │    │    │ PS.2: Access Control for Repos     │        │
│  │ 🔧 Security Champions program      │    │    │       - RBAC policies              │        │
│  │ 📋 Training records                │    │    │       - IAM integration            │        │
│  └────────────┬───────────────────────┘    │    │       - Audit logging              │        │
│               │                             │    └─────────────┬──────────────────────┘        │
│               ▼                             │                  │                                │
│  ┌────────────────────────────────────┐    │                  ▼                                │
│  │ PO.3: Create Security Requirements │────┼───┐  ┌────────────────────────────────────┐      │
│  │ 🔧 Threat modeling                 │    │   │  │ PS.3: Protect Software Artifacts   │      │
│  │ 📋 Requirements docs               │    │   └─▶│       - OCI registry signing       │      │
│  └────────────┬───────────────────────┘    │      │       - Cosign + KMS               │      │
│               │                             │      │       - Immutable storage          │      │
│               ▼                             │      └────────────────────────────────────┘      │
│  ┌────────────────────────────────────┐    │                                                   │
│  │ PO.4: Define Metrics & KPIs        │◀───┼─────────────────┐                                │
│  │ 🔧 Prometheus, Grafana             │    │                 │ Feedback: Metrics              │
│  │ 📋 KPI dashboard                   │    │                 │                                │
│  └────────────┬───────────────────────┘    │                 │                                │
│               │                             │                 │                                │
│  ┌────────────▼───────────────────────┐    │                 │                                │
│  │ PO.5: Secure Supply Chain          │────┼───┐             │                                │
│  │ 🔧 SBOM (Syft)                     │    │   │             │                                │
│  │ 🔧 Signatures (Cosign)             │    │   │             │                                │
│  │ 🔧 SLSA provenance                 │    │   │             │                                │
│  └────────────────────────────────────┘    │   │             │                                │
│                                             │   │             │                                │
└─────────────────────────────────────────────┼───┼─────────────┼────────────────────────────────┘
                                              │   │             │
┌─────────────────────────────────────────────┼───┼─────────────┼────────────────────────────────┐
│  QUADRANT 3: PRODUCE WELL-SECURED SOFTWARE  │   │             │                                │
│  (PW) - 19 Practices                        │   │             │                                │
│  Design → Development → Testing → Deploy    │   │             │                                │
├─────────────────────────────────────────────┼───┼─────────────┼────────────────────────────────┤
│                                             │   │             │                                │
│  ┌─────────── DESIGN PHASE ─────────────┐  │   │             │                                │
│  │                                       │  │   │             │                                │
│  │  ┌──────────────────────────────┐    │◀─┘   │             │                                │
│  │  │ PW.1: Secure Design          │    │      │             │                                │
│  │  │       Principles              │    │      │             │                                │
│  │  │ 🔧 Architecture review        │    │      │             │
│  │  └────────────┬─────────────────┘    │      │             │                                │
│  │               ▼                       │      │             │                                │
│  │  ┌──────────────────────────────┐    │      │             │                                │
│  │  │ PW.2: Review Code            │◀───┼──────┘             │                                │
│  │  │ 🔧 SonarQube SAST            │    │                    │                                │
│  │  │ 🔧 PR reviews                │    │                    │                                │
│  │  └────────────┬─────────────────┘    │                    │                                │
│  └───────────────┼───────────────────────┘                    │                                │
│                  ▼                                             │                                │
│  ┌─────────── DEVELOPMENT PHASE ─────────┐                    │                                │
│  │                                        │                    │                                │
│  │  ┌──────────────────────────────┐     │                    │                                │
│  │  │ PW.4: Reuse Existing         │     │                    │                                │
│  │  │       Software               │     │                    │                                │
│  │  │ 🔧 Dependency management     │     │                    │                                │
│  │  └────────────┬─────────────────┘     │                    │                                │
│  │               ▼                        │                    │                                │
│  │  ┌──────────────────────────────┐     │                    │                                │
│  │  │ PW.5: Create Well-Secured    │◀────┼────────────────────┘ Feedback from testing         │
│  │  │       Software               │     │                                                     │
│  │  │ 🔧 Secure coding standards   │     │                                                     │
│  │  └────────────┬─────────────────┘     │                                                     │
│  │               ▼                        │                                                     │
│  │  ┌──────────────────────────────┐     │                                                     │
│  │  │ PW.6: Configure Security     │     │    ┌────────────────────────────────┐              │
│  │  │       Tools                  │◀────┼────│  34 Security Tools Hub         │              │
│  │  │ 🔧 SAST, DAST, SCA          │     │    │  - SAST: SonarQube, Semgrep    │              │
│  │  └────────────┬─────────────────┘     │    │  - SCA: Trivy, Grype           │              │
│  └───────────────┼────────────────────────┘    │  - Container: Syft, Cosign     │              │
│                  ▼                             │  - IaC: Checkov, tfsec         │              │
│  ┌─────────── TESTING PHASE ──────────┐       │  - DAST: ZAP, Nuclei           │              │
│  │                                     │       │  - Runtime: Falco, Wazuh       │              │
│  │  ┌──────────────────────────────┐  │       └────────────────────────────────┘              │
│  │  │ PW.7: Test for               │◀─┼─────────────────┐                                     │
│  │  │       Vulnerabilities        │  │                 │                                     │
│  │  │ 🔧 Trivy, Grype, ZAP        │  │                 │                                     │
│  │  └────────────┬─────────────────┘  │                 │                                     │
│  │               ▼                     │                 │                                     │
│  │  ┌──────────────────────────────┐  │                 │                                     │
│  │  │ PW.8: Prepare for            │  │                 │                                     │
│  │  │       Deployment             │  │                 │                                     │
│  │  │ 🔧 Atlantis, Helm            │  │                 │                                     │
│  │  └────────────┬─────────────────┘  │                 │                                     │
│  │               ▼                     │                 │                                     │
│  │  ┌──────────────────────────────┐  │                 │                                     │
│  │  │ PW.9: Verify Software        │◀─┼───┐             │                                     │
│  │  │       Integrity              │  │   │             │                                     │
│  │  │ 🔧 Cosign, in-toto, SLSA    │  │   │             │                                     │
│  │  └────────────┬─────────────────┘  │   │             │                                     │
│  └───────────────┼─────────────────────┘   │             │                                     │
│                  │                         │             │                                     │
└──────────────────┼─────────────────────────┼─────────────┼─────────────────────────────────────┘
                   │                         │             │
┌──────────────────┼─────────────────────────┼─────────────┼─────────────────────────────────────┐
│  QUADRANT 4: RESPOND TO VULNERABILITIES     │             │                                     │
│  (RV) - 9 Practices                         │             │                                     │
├─────────────────────────────────────────────┼─────────────┼─────────────────────────────────────┤
│                                             │             │                                     │
│                  ┌──────────────────────────▼─────────────▼────┐                               │
│                  │ RV.1: Identify Vulnerabilities              │                               │
│                  │ 🔧 Trivy, Grype, OSV-Scanner                │                               │
│                  │ 📋 CVE database, NVD feeds                  │                               │
│                  └──────────────┬──────────────────────────────┘                               │
│                                 ▼                                                               │
│                  ┌──────────────────────────────────────────────┐                              │
│                  │ RV.2: Assess and Triage Vulnerabilities      │                              │
│                  │ 🔧 Dependency Track                          │                              │
│                  │ 🔧 Risk scoring (CVSS)                       │───────────────┐              │
│                  │ 📋 Risk assessments                          │               │              │
│                  └──────────────┬───────────────────────────────┘               │              │
│                                 ▼                                                │              │
│                  ┌──────────────────────────────────────────────┐               │              │
│                  │ RV.3: Remediate Vulnerabilities              │               │              │
│                  │ 🔧 Patch management                          │               │              │
│                  │ 🔧 Automated updates                         │               │              │
│                  │ 📋 Remediation records                       │               │              │
│                  └──────────────┬───────────────────────────────┘               │              │
│                                 │                                                │              │
│                                 └───────────────────┐                            │              │
│                                        Feedback     │                            │              │
│                                                     │                            │              │
└─────────────────────────────────────────────────────┼────────────────────────────┼──────────────┘
                                                      │                            │
                                                      ▼                            │
                                         Lessons Learned (PO.2)                    │
                                                                                   │
                                                                                   ▼
                                                                          Metrics Update (PO.4)

┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              EVIDENCE COLLECTION & STORAGE                                      │
├─────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────────┐     │
│   │                           Evidence Dashboard & Registry                              │     │
│   │                                                                                       │     │
│   │  📊 GCS Bucket (7-year retention)    📊 PostgreSQL (metadata)                       │     │
│   │  📊 n8n Workflow (automation)        📊 Grafana (visualization)                     │     │
│   │                                                                                       │     │
│   │  Evidence Sources:                                                                   │     │
│   │    ├─ PO.4 ──▶ Metrics and KPIs                                                     │     │
│   │    ├─ PS.3 ──▶ Artifact signatures and manifests                                    │     │
│   │    ├─ PW.9 ──▶ Attestations (SLSA, in-toto)                                        │     │
│   │    └─ RV.2 ──▶ Vulnerability reports and risk assessments                          │     │
│   │                                                                                       │     │
│   └───────────────────────────────────────────────────────────────────────────────────── ┘     │
│                                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘

Legend:
─────▶  Direct dependency
- - -▶  Feedback loop
······▶ Evidence/tool flow
🔧      Tool or implementation
📋      Evidence artifact
```

## Practice Details by Quadrant

### QUADRANT 1: PREPARE ORGANIZATION (PO) - 12 Practices

#### PO.1: Define Secure Development Practices
- **Sub-practices**: PO.1.1, PO.1.2, PO.1.3
- **Tools**: git-secrets, pre-commit hooks, policy documentation
- **Evidence**: Security policies, SDLC documentation, standards
- **Dependencies**: Foundation for all other practices

#### PO.2: Implement Secure Development Training
- **Sub-practices**: PO.2.1, PO.2.2
- **Tools**: Security Champions program, training platforms
- **Evidence**: Training records, certifications, awareness metrics
- **Dependencies**: PO.1 → PO.2

#### PO.3: Create Security Requirements
- **Sub-practices**: PO.3.1, PO.3.2, PO.3.3
- **Tools**: Threat modeling, requirements management
- **Evidence**: Requirements documents, threat models, risk analysis
- **Dependencies**: PO.2 → PO.3; PO.3 → PW.1

#### PO.4: Define Metrics and KPIs
- **Sub-practices**: PO.4.1, PO.4.2
- **Tools**: Prometheus, Grafana, custom dashboards
- **Evidence**: KPI dashboard, trend analysis, compliance reports
- **Dependencies**: PO.3 → PO.4; receives feedback from RV.2

#### PO.5: Secure Supply Chain
- **Sub-practices**: PO.5.1, PO.5.2
- **Tools**: Syft (SBOM), Cosign (signing), SLSA (provenance)
- **Evidence**: SBOM files, signatures, provenance attestations
- **Dependencies**: PO.1 → PO.5; PO.5 → PS.3

---

### QUADRANT 2: PROTECT SOFTWARE (PS) - 7 Practices

#### PS.1: Store Code in Version Control
- **Sub-practices**: PS.1.1
- **Tools**: Gitea, Git signed commits, branch protection
- **Evidence**: Commit logs, branch policies, access records
- **Dependencies**: PO.1 → PS.1; PS.1 → PW.2

#### PS.2: Access Control for Repositories
- **Sub-practices**: PS.2.1
- **Tools**: RBAC, IAM policies, audit logging
- **Evidence**: Access audit logs, permission matrices, policy documents
- **Dependencies**: PS.1 → PS.2

#### PS.3: Protect Software Artifacts
- **Sub-practices**: PS.3.1, PS.3.2
- **Tools**: OCI registry, Cosign, KMS, immutable storage
- **Evidence**: Artifact signatures, access logs, encryption records
- **Dependencies**: PS.2 → PS.3; PO.5 → PS.3; PS.3 → PW.9

---

### QUADRANT 3: PRODUCE WELL-SECURED SOFTWARE (PW) - 19 Practices

#### Design Phase

##### PW.1: Use Secure Design Principles
- **Sub-practices**: PW.1.1, PW.1.2, PW.1.3
- **Tools**: Architecture review, threat modeling
- **Evidence**: Design documents, threat models, security patterns
- **Dependencies**: PO.3 → PW.1; PW.1 → PW.2

##### PW.2: Review Code
- **Sub-practices**: PW.2.1
- **Tools**: SonarQube, PR reviews, manual review
- **Evidence**: Review records, SAST reports, approval logs
- **Dependencies**: PS.1 → PW.2; PW.2 → PW.4

#### Development Phase

##### PW.4: Reuse Existing Software
- **Sub-practices**: PW.4.1, PW.4.4
- **Tools**: Dependency management, license checking
- **Evidence**: Dependency lists, SBOM, license compliance
- **Dependencies**: PW.2 → PW.4; PW.4 → PW.5

##### PW.5: Create Well-Secured Software
- **Sub-practices**: PW.5.1
- **Tools**: Secure coding standards, linters, formatters
- **Evidence**: Code quality reports, standards compliance
- **Dependencies**: PW.4 → PW.5; receives feedback from PW.7

##### PW.6: Configure Security Tools
- **Sub-practices**: PW.6.1, PW.6.2
- **Tools**: SAST, DAST, SCA configuration
- **Evidence**: Tool configurations, scan results
- **Dependencies**: PW.5 → PW.6; integrates with 34 security tools

#### Testing Phase

##### PW.7: Test for Vulnerabilities
- **Sub-practices**: PW.7.1, PW.7.2
- **Tools**: Trivy, Grype, OWASP ZAP, Nuclei
- **Evidence**: Scan reports, DAST results, CVE lists
- **Dependencies**: PW.6 → PW.7; PW.7 → RV.1; provides feedback to PW.5

##### PW.8: Prepare for Deployment
- **Sub-practices**: PW.8.1, PW.8.2
- **Tools**: Atlantis, Helm, Kubernetes manifests
- **Evidence**: Deployment configurations, release notes
- **Dependencies**: PW.7 → PW.8; PW.8 → PW.9

##### PW.9: Verify Software Integrity
- **Sub-practices**: PW.9.1, PW.9.2
- **Tools**: Cosign, in-toto, SLSA provenance
- **Evidence**: Signatures, attestations, hashes
- **Dependencies**: PS.3 → PW.9; PW.9 → RV.1

---

### QUADRANT 4: RESPOND TO VULNERABILITIES (RV) - 9 Practices

#### RV.1: Identify Vulnerabilities
- **Sub-practices**: RV.1.1, RV.1.2, RV.1.3
- **Tools**: Trivy, Grype, OSV-Scanner, NVD feeds
- **Evidence**: CVE reports, vulnerability lists, scan results
- **Dependencies**: PW.7 → RV.1; PW.9 → RV.1; RV.1 → RV.2

#### RV.2: Assess and Triage Vulnerabilities
- **Sub-practices**: RV.2.1, RV.2.2
- **Tools**: Dependency Track, CVSS scoring, risk analysis
- **Evidence**: Risk assessments, triage decisions, priority lists
- **Dependencies**: RV.1 → RV.2; provides feedback to PO.4

#### RV.3: Remediate Vulnerabilities
- **Sub-practices**: RV.3.1, RV.3.2, RV.3.3, RV.3.4
- **Tools**: Patch management, automated updates, hotfix deployment
- **Evidence**: Patch records, remediation logs, verification results
- **Dependencies**: RV.2 → RV.3; provides feedback to PO.2 and PW.7

---

## Practice Dependencies

### Primary Flows
1. **Policy to Implementation**: PO.1 → PS.1 → PW.2
2. **Requirements to Design**: PO.3 → PW.1 → PW.2
3. **Supply Chain**: PO.5 → PS.3 → PW.9
4. **Testing to Response**: PW.7 → RV.1 → RV.2 → RV.3

### Feedback Loops
1. **Vulnerability Lessons**: RV.3 → PO.2 (training updates)
2. **Metrics Update**: RV.2 → PO.4 (KPI refinement)
3. **Code Improvements**: PW.7 → PW.5 (secure coding)

---

## Evidence Flows

All practices generate evidence that flows to the central Evidence Dashboard:

### Evidence Sources
- **PO.4**: Metrics, KPIs, compliance reports
- **PS.3**: Artifact signatures, manifests, access logs
- **PW.9**: Attestations (SLSA, in-toto), integrity proofs
- **RV.2**: Vulnerability reports, risk assessments

### Evidence Storage
- **GCS Bucket**: Long-term immutable storage (7-year retention)
- **PostgreSQL**: Metadata, indexes, query interface
- **n8n Workflow**: Automated collection and processing
- **Grafana**: Visualization and dashboards

---

## Tool Integration Points

### Central Integration Hub
34 security tools integrate at multiple points:

- **PW.6**: Tool configuration and initialization
- **PW.7**: Active testing and scanning
- **RV.1**: Vulnerability detection and identification

### Tool Categories
1. **SAST**: SonarQube, Semgrep, Bandit
2. **SCA**: Trivy, Grype, OSV-Scanner
3. **Container**: Syft, Cosign, Docker Bench
4. **IaC**: Checkov, tfsec, Terrascan
5. **DAST**: OWASP ZAP, Nuclei
6. **Runtime**: Falco, Wazuh, osquery
7. **Monitoring**: Prometheus, Grafana, Loki

---

## Rendering Instructions

### Mermaid
```bash
mmdc -i SSDF_PRACTICE_FLOW.md -o ssdf-practice-flow.png -t dark -b transparent -w 2400 -h 2400
```

### PlantUML
```bash
docker run -v $(pwd):/data plantuml/plantuml -tpng /data/SSDF_PRACTICE_FLOW.md
```

---

## References

- **NIST SP 800-218**: Secure Software Development Framework Version 1.1
- **SSDF Practice Catalog**: All 47 tasks across 4 practice groups
- **CISA Attestation Form**: Alignment with federal requirements
