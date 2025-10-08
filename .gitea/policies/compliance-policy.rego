package compliance.ssdf

import future.keywords.contains
import future.keywords.if
import future.keywords.in

default compliant := false

# SSDF Compliance Policy
# Validates compliance with NIST SP 800-218 and CMMC Level 2

# Main compliance rule - all requirements must be met
compliant if {
    cmmc_controls_validated
    ssdf_practices_verified
    evidence_complete
    attestation_valid
    audit_trail_maintained
}

# CMMC Control Validation (mapped to SSDF)
cmmc_controls_validated if {
    validated_controls := cmmc_level2_controls & input.implemented_controls
    coverage := count(validated_controls) / count(cmmc_level2_controls)
    coverage >= 0.95  # 95% coverage required
}

# CMMC Level 2 Control Requirements
cmmc_level2_controls := {
    # Access Control (AC)
    "AC.L1-3.1.1", "AC.L1-3.1.2", "AC.L1-3.1.20", "AC.L1-3.1.22",
    "AC.L2-3.1.3", "AC.L2-3.1.5", "AC.L2-3.1.6", "AC.L2-3.1.7",
    "AC.L2-3.1.8", "AC.L2-3.1.9", "AC.L2-3.1.10", "AC.L2-3.1.11",
    "AC.L2-3.1.12", "AC.L2-3.1.13", "AC.L2-3.1.14", "AC.L2-3.1.15",

    # Audit and Accountability (AU)
    "AU.L1-3.3.1", "AU.L1-3.3.2",
    "AU.L2-3.3.3", "AU.L2-3.3.4", "AU.L2-3.3.5", "AU.L2-3.3.6",
    "AU.L2-3.3.7", "AU.L2-3.3.8", "AU.L2-3.3.9",

    # Configuration Management (CM)
    "CM.L1-3.4.1", "CM.L1-3.4.2",
    "CM.L2-3.4.3", "CM.L2-3.4.4", "CM.L2-3.4.5", "CM.L2-3.4.6",
    "CM.L2-3.4.7", "CM.L2-3.4.8", "CM.L2-3.4.9",

    # Identification and Authentication (IA)
    "IA.L1-3.5.1", "IA.L1-3.5.2",
    "IA.L2-3.5.3", "IA.L2-3.5.4", "IA.L2-3.5.5", "IA.L2-3.5.6",
    "IA.L2-3.5.7", "IA.L2-3.5.8", "IA.L2-3.5.9", "IA.L2-3.5.10",

    # Incident Response (IR)
    "IR.L1-3.6.1", "IR.L1-3.6.2",
    "IR.L2-3.6.3",

    # Maintenance (MA)
    "MA.L1-3.7.1", "MA.L1-3.7.2",
    "MA.L2-3.7.3", "MA.L2-3.7.4", "MA.L2-3.7.5", "MA.L2-3.7.6",

    # Media Protection (MP)
    "MP.L1-3.8.1", "MP.L1-3.8.2", "MP.L1-3.8.3",
    "MP.L2-3.8.4", "MP.L2-3.8.5", "MP.L2-3.8.6", "MP.L2-3.8.7",
    "MP.L2-3.8.8", "MP.L2-3.8.9",

    # Physical Protection (PE)
    "PE.L1-3.10.1", "PE.L1-3.10.2",
    "PE.L2-3.10.3", "PE.L2-3.10.4", "PE.L2-3.10.5", "PE.L2-3.10.6",

    # Risk Assessment (RA)
    "RA.L1-3.11.1",
    "RA.L2-3.11.2", "RA.L2-3.11.3",

    # System and Communications Protection (SC)
    "SC.L1-3.13.1", "SC.L1-3.13.5",
    "SC.L2-3.13.2", "SC.L2-3.13.3", "SC.L2-3.13.4", "SC.L2-3.13.6",
    "SC.L2-3.13.7", "SC.L2-3.13.8", "SC.L2-3.13.9", "SC.L2-3.13.10",
    "SC.L2-3.13.11", "SC.L2-3.13.12", "SC.L2-3.13.13", "SC.L2-3.13.14",
    "SC.L2-3.13.15", "SC.L2-3.13.16",

    # System and Information Integrity (SI)
    "SI.L1-3.14.1", "SI.L1-3.14.2", "SI.L1-3.14.3",
    "SI.L2-3.14.4", "SI.L2-3.14.5", "SI.L2-3.14.6", "SI.L2-3.14.7"
}

# SSDF Practice Verification (All 42 tasks)
ssdf_practices_verified if {
    all_practices_implemented
    practice_evidence_exists
    practice_metrics_collected
}

all_practices_implemented if {
    required_practices := ssdf_all_practices
    implemented := {p | some p in input.ssdf_practices; p in required_practices}
    count(implemented) == count(required_practices)
}

# Complete list of SSDF practices
ssdf_all_practices := {
    # Prepare the Organization (PO)
    "PO.1.1", "PO.1.2", "PO.1.3",
    "PO.3.1", "PO.3.2", "PO.3.3",
    "PO.4.1", "PO.4.2",
    "PO.5.1", "PO.5.2",

    # Protect Software (PS)
    "PS.1.1",
    "PS.2.1",
    "PS.3.1", "PS.3.2", "PS.3.3", "PS.3.4",

    # Produce Well-Secured Software (PW)
    "PW.1.1", "PW.1.2", "PW.1.3",
    "PW.2.1",
    "PW.3.1",
    "PW.4.1", "PW.4.2", "PW.4.4",
    "PW.5.1",
    "PW.6.1", "PW.6.2",
    "PW.7.1", "PW.7.2", "PW.7.3",
    "PW.8.1", "PW.8.2",
    "PW.9.1", "PW.9.2",

    # Respond to Vulnerabilities (RV)
    "RV.1.1", "RV.1.2", "RV.1.3",
    "RV.2.1", "RV.2.2",
    "RV.3.1", "RV.3.2", "RV.3.3"
}

# Practice evidence requirements
practice_evidence_exists if {
    every practice in input.ssdf_practices {
        practice_has_evidence(practice)
    }
}

practice_has_evidence(practice) if {
    evidence := input.evidence[practice]
    evidence.artifacts != null
    count(evidence.artifacts) > 0
    evidence.timestamp != null
    evidence.hash != null
}

# Practice metrics collection
practice_metrics_collected if {
    metrics_complete
    metrics_current
    metrics_measurable
}

metrics_complete if {
    required_metrics := {
        "code_coverage",
        "vulnerability_count",
        "mean_time_to_remediate",
        "dependency_updates",
        "security_training_completion",
        "incident_response_time"
    }

    provided := {m | some m in input.metrics; m in required_metrics}
    count(provided) == count(required_metrics)
}

metrics_current if {
    every metric in input.metrics {
        metric_age_days(metric) <= 30
    }
}

metric_age_days(metric) := days if {
    timestamp := time.parse_rfc3339_ns(metric.timestamp)
    now := time.now_ns()
    diff := now - timestamp
    days := diff / (1000000000 * 86400)
}

metrics_measurable if {
    input.metrics.code_coverage >= 70
    input.metrics.vulnerability_count.critical == 0
    input.metrics.mean_time_to_remediate <= 14  # days
    input.metrics.security_training_completion >= 90  # percentage
}

# Evidence completeness checks
evidence_complete if {
    has_all_required_evidence
    evidence_properly_signed
    evidence_chain_of_custody
}

has_all_required_evidence if {
    required_evidence := {
        "sbom_spdx",
        "sbom_cyclonedx",
        "vulnerability_scan",
        "sast_report",
        "dast_report",
        "dependency_check",
        "code_review_log",
        "build_attestation",
        "deployment_log",
        "incident_response_plan",
        "security_training_records",
        "audit_logs"
    }

    provided := {e | some e in input.evidence_files; e in required_evidence}
    count(provided) == count(required_evidence)
}

evidence_properly_signed if {
    every file in input.evidence_files {
        file_has_valid_signature(file)
    }
}

file_has_valid_signature(file) if {
    file.signature != null
    file.signature.algorithm in {"SHA256", "SHA512"}
    file.signature.verified == true
}

evidence_chain_of_custody if {
    input.evidence.chain_of_custody != null
    every entry in input.evidence.chain_of_custody {
        entry.timestamp != null
        entry.hash != null
        entry.actor != null
        entry.action != null
    }
}

# Attestation validation
attestation_valid if {
    attestation_format_correct
    attestation_signed
    attestation_not_expired
}

attestation_format_correct if {
    input.attestation.version == "1.0"
    input.attestation.type == "NIST-SSDF-SP-800-218"
    input.attestation.ssdf_version in {"1.1", "1.0"}
    input.attestation.compliance_level in {"Full", "Partial"}
}

attestation_signed if {
    input.attestation.signature != null
    input.attestation.signature.key_id != null
    input.attestation.signature.verified == true
}

attestation_not_expired if {
    expiry := time.parse_rfc3339_ns(input.attestation.validity.expires)
    now := time.now_ns()
    expiry > now
}

# Audit trail requirements
audit_trail_maintained if {
    audit_logs_complete
    audit_logs_immutable
    audit_retention_policy
}

audit_logs_complete if {
    required_events := {
        "build_started",
        "security_scan_completed",
        "vulnerabilities_detected",
        "deployment_approved",
        "production_deployed",
        "incident_detected",
        "patch_applied"
    }

    logged := {e | some e in input.audit_log.events; e.type in required_events}
    count(logged) > 0
}

audit_logs_immutable if {
    input.audit_log.immutable == true
    input.audit_log.blockchain_hash != null
}

audit_retention_policy if {
    input.audit_log.retention_days >= 365
    input.audit_log.archived == true
}

# Generate compliance violations
violations[msg] {
    not cmmc_controls_validated
    coverage := count(input.implemented_controls & cmmc_level2_controls) / count(cmmc_level2_controls)
    msg := sprintf("CMMC Level 2 coverage %.1f%% below required 95%%", [coverage * 100])
}

violations[msg] {
    not all_practices_implemented
    missing := ssdf_all_practices - input.ssdf_practices
    msg := sprintf("Missing SSDF practices: %v", [missing])
}

violations[msg] {
    not has_all_required_evidence
    missing := required_evidence - input.evidence_files
    msg := sprintf("Missing evidence files: %v", [missing])
}

violations[msg] {
    not attestation_valid
    msg := "Invalid or expired attestation document"
}

violations[msg] {
    not audit_logs_complete
    msg := "Incomplete audit trail"
}

violations[msg] {
    input.metrics.code_coverage < 70
    msg := sprintf("Code coverage %.1f%% below minimum 70%%", [input.metrics.code_coverage])
}

violations[msg] {
    input.metrics.vulnerability_count.critical > 0
    msg := sprintf("Critical vulnerabilities found: %d", [input.metrics.vulnerability_count.critical])
}

# Compliance score calculation
compliance_score := score if {
    cmmc_weight := 30
    ssdf_weight := 30
    evidence_weight := 20
    attestation_weight := 10
    audit_weight := 10

    cmmc_score := count(input.implemented_controls & cmmc_level2_controls) / count(cmmc_level2_controls) * cmmc_weight
    ssdf_score := count(input.ssdf_practices & ssdf_all_practices) / count(ssdf_all_practices) * ssdf_weight
    evidence_score := count(input.evidence_files & required_evidence) / count(required_evidence) * evidence_weight
    attestation_score := attestation_weight * attestation_valid
    audit_score := audit_weight * audit_trail_maintained

    score := cmmc_score + ssdf_score + evidence_score + attestation_score + audit_score
}

# Compliance level determination
compliance_level := "FULL" if compliance_score >= 95
compliance_level := "SUBSTANTIAL" if {compliance_score >= 80; compliance_score < 95}
compliance_level := "PARTIAL" if {compliance_score >= 60; compliance_score < 80}
compliance_level := "NON-COMPLIANT" if compliance_score < 60

# Generate recommendations
recommendations[action] {
    not cmmc_controls_validated
    action := "Implement missing CMMC Level 2 controls"
}

recommendations[action] {
    not all_practices_implemented
    action := "Complete implementation of all SSDF practices"
}

recommendations[action] {
    not evidence_complete
    action := "Collect and sign all required evidence artifacts"
}

recommendations[action] {
    not attestation_valid
    action := "Generate and sign valid SSDF attestation document"
}

recommendations[action] {
    not metrics_current
    action := "Update compliance metrics (older than 30 days)"
}

# Policy decision
decision := {
    "compliant": compliant,
    "compliance_score": compliance_score,
    "compliance_level": compliance_level,
    "violations": violations,
    "recommendations": recommendations,
    "cmmc_coverage": count(input.implemented_controls & cmmc_level2_controls) / count(cmmc_level2_controls) * 100,
    "ssdf_coverage": count(input.ssdf_practices & ssdf_all_practices) / count(ssdf_all_practices) * 100,
    "timestamp": input.timestamp,
    "next_review": time.add_date(time.now_ns(), 0, 0, 30)  # 30 days
}