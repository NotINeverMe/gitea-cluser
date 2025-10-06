#!/bin/bash
# Security Tools Installation Script
# CMMC 2.0: SI.L2-3.14.1 (Flaw Remediation)
# NIST SP 800-171: 3.14.1 (System Flaws)

set -euo pipefail

# Configuration
readonly INSTALL_FALCO="${INSTALL_FALCO:-true}"
readonly INSTALL_OSQUERY="${INSTALL_OSQUERY:-true}"
readonly INSTALL_WAZUH="${INSTALL_WAZUH:-true}"
readonly COMPLIANCE_MODE="${COMPLIANCE_MODE:-true}"
readonly LOG_FILE="/var/log/security-tools-install.log"

# Logging
log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

# Install Trivy vulnerability scanner
install_trivy() {
    log "Installing Trivy vulnerability scanner..."

    # Add Trivy repository
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -
    echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | \
        tee /etc/apt/sources.list.d/trivy.list

    # Install Trivy
    apt-get update
    apt-get install -y trivy

    # Download vulnerability database
    trivy image --download-db-only

    # Configure Trivy
    mkdir -p /etc/trivy
    cat << EOF > /etc/trivy/trivy.yaml
# Trivy Configuration for CMMC Compliance
format: json
severity:
  - CRITICAL
  - HIGH
  - MEDIUM
vuln-type:
  - os
  - library
ignore-unfixed: false
security-checks:
  - vuln
  - config
  - secret
cache-dir: /var/cache/trivy
db-repository: ghcr.io/aquasecurity/trivy-db
EOF

    # Create scanning script
    cat << 'EOF' > /usr/local/bin/trivy-scan
#!/bin/bash
# Automated Trivy scanning with evidence collection

IMAGE="${1:-}"
OUTPUT_DIR="/var/log/trivy-scans"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 <image>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Run scan and save results
trivy image \
    --format json \
    --output "${OUTPUT_DIR}/${TIMESTAMP}-scan.json" \
    --severity CRITICAL,HIGH,MEDIUM \
    "$IMAGE"

# Generate summary
trivy image \
    --format table \
    --severity CRITICAL,HIGH \
    "$IMAGE" > "${OUTPUT_DIR}/${TIMESTAMP}-summary.txt"

# Calculate evidence hash
sha256sum "${OUTPUT_DIR}/${TIMESTAMP}-"* > "${OUTPUT_DIR}/${TIMESTAMP}-evidence.sha256"

echo "Scan complete. Results in ${OUTPUT_DIR}/${TIMESTAMP}-*"
EOF
    chmod +x /usr/local/bin/trivy-scan

    log "Trivy installation completed"
}

# Install Grype CVE scanner
install_grype() {
    log "Installing Grype CVE scanner..."

    # Download and install Grype
    curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

    # Update vulnerability database
    grype db update

    # Configure Grype
    mkdir -p /etc/grype
    cat << EOF > /etc/grype/config.yaml
# Grype Configuration
check-for-app-update: true
fail-on-severity: "critical"
only-fixed: false
scope: "all-layers"
quiet: false
log:
  level: "info"
  file: "/var/log/grype.log"
db:
  cache-dir: "/var/cache/grype"
  update-url: "https://toolbox-data.anchore.io/grype/databases/listing.json"
  auto-update: true
  validate-by-hash-on-start: false
registry:
  insecure-skip-tls-verify: false
  insecure-use-http: false
output:
  - json
  - table
EOF

    # Create scanning script
    cat << 'EOF' > /usr/local/bin/grype-scan
#!/bin/bash
# Automated Grype scanning with SBOM generation

TARGET="${1:-}"
OUTPUT_DIR="/var/log/grype-scans"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

if [ -z "$TARGET" ]; then
    echo "Usage: $0 <target>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Generate SBOM with Syft
syft "$TARGET" -o json > "${OUTPUT_DIR}/${TIMESTAMP}-sbom.json"

# Run Grype scan
grype "$TARGET" \
    --output json \
    --file "${OUTPUT_DIR}/${TIMESTAMP}-vulnerabilities.json"

# Generate summary
grype "$TARGET" \
    --only-fixed \
    --fail-on critical > "${OUTPUT_DIR}/${TIMESTAMP}-summary.txt"

# Calculate evidence hash
sha256sum "${OUTPUT_DIR}/${TIMESTAMP}-"* > "${OUTPUT_DIR}/${TIMESTAMP}-evidence.sha256"

echo "Scan complete. Results in ${OUTPUT_DIR}/${TIMESTAMP}-*"
EOF
    chmod +x /usr/local/bin/grype-scan

    # Install Syft for SBOM generation
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

    log "Grype installation completed"
}

# Install Falco runtime security
install_falco() {
    if [ "$INSTALL_FALCO" != "true" ]; then
        log "Skipping Falco installation"
        return
    fi

    log "Installing Falco runtime security..."

    # Add Falco repository
    curl -s https://falco.org/repo/falcosecurity-3672BA8F.asc | apt-key add -
    echo "deb https://download.falco.org/packages/deb stable main" | \
        tee /etc/apt/sources.list.d/falcosecurity.list

    # Install kernel headers
    apt-get update
    apt-get install -y linux-headers-$(uname -r) dkms

    # Install Falco
    apt-get install -y falco

    # Configure Falco for compliance monitoring
    cat << 'EOF' > /etc/falco/falco_rules.local.yaml
# CMMC/NIST Compliance Rules for Falco

- rule: Unauthorized Process in Container
  desc: Detect unauthorized processes running in containers
  condition: >
    spawned_process and container and
    not proc.name in (allowed_processes)
  output: >
    Unauthorized process in container (user=%user.name command=%proc.cmdline container=%container.info)
  priority: WARNING
  tags: [container, process, compliance]

- rule: Sensitive File Access
  desc: Detect access to sensitive files
  condition: >
    open_read and
    fd.name in (/etc/shadow, /etc/gshadow, /etc/security/opasswd)
  output: >
    Sensitive file opened for reading (user=%user.name command=%proc.cmdline file=%fd.name)
  priority: WARNING
  tags: [filesystem, compliance]

- rule: Modification of Critical Files
  desc: Detect modifications to critical system files
  condition: >
    open_write and
    fd.name in (/etc/passwd, /etc/shadow, /etc/sudoers, /etc/pam.d, /etc/security)
  output: >
    Critical file opened for writing (user=%user.name command=%proc.cmdline file=%fd.name)
  priority: CRITICAL
  tags: [filesystem, compliance]

- rule: Outbound Network Connection
  desc: Detect outbound connections from unexpected processes
  condition: >
    outbound and
    not proc.name in (curl, wget, apt-get, git, docker)
  output: >
    Unexpected outbound connection (command=%proc.cmdline connection=%fd.name)
  priority: NOTICE
  tags: [network, compliance]

- rule: Privilege Escalation Detected
  desc: Detect potential privilege escalation
  condition: >
    spawned_process and
    proc.name in (sudo, su) and
    not user.name in (allowed_sudo_users)
  output: >
    Privilege escalation attempt (user=%user.name command=%proc.cmdline)
  priority: CRITICAL
  tags: [users, compliance]

- macro: allowed_processes
  condition: proc.name in (bash, sh, python, java, node)

- macro: allowed_sudo_users
  condition: user.name in (root, ubuntu, admin)

- list: sensitive_files
  items: [/etc/shadow, /etc/sudoers, /etc/pam.d]

- list: critical_binaries
  items: [/bin/bash, /bin/sh, /usr/bin/sudo]
EOF

    # Configure Falco output
    cat << EOF >> /etc/falco/falco.yaml
# Additional output configuration
json_output: true
json_include_output_property: true
log_stderr: true
log_syslog: true
log_level: info

# File output for compliance evidence
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/falco.json

# Program output for alerting
program_output:
  enabled: false
  program: "jq '{text: .output}' | curl -d @- -X POST https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Compliance monitoring
webserver:
  enabled: true
  listen_port: 8765
  k8s_audit_endpoint: /k8s-audit
  ssl_enabled: false
EOF

    # Enable and start Falco
    systemctl enable falco
    systemctl start falco

    log "Falco installation completed"
}

# Install osquery for system monitoring
install_osquery() {
    if [ "$INSTALL_OSQUERY" != "true" ]; then
        log "Skipping osquery installation"
        return
    fi

    log "Installing osquery system monitoring..."

    # Download and install osquery
    export OSQUERY_KEY=1484120AC4E9F8A1A577AEEE97A80C63C9D8B80B
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $OSQUERY_KEY
    echo "deb [arch=amd64] https://pkg.osquery.io/deb deb main" | \
        tee /etc/apt/sources.list.d/osquery.list

    apt-get update
    apt-get install -y osquery

    # Configure osquery for compliance monitoring
    cat << 'EOF' > /etc/osquery/osquery.conf
{
  "options": {
    "config_plugin": "filesystem",
    "logger_plugin": "filesystem",
    "logger_path": "/var/log/osquery",
    "disable_logging": "false",
    "schedule_splay_percent": "10",
    "pidfile": "/var/run/osquery.pidfile",
    "events_expiry": "3600",
    "verbose": "false",
    "worker_threads": "2",
    "enable_monitor": "true",
    "disable_events": "false",
    "disable_audit": "false",
    "audit_allow_config": "true",
    "audit_allow_sockets": "true",
    "host_identifier": "hostname",
    "enable_syslog": "true"
  },

  "schedule": {
    "system_info": {
      "query": "SELECT hostname, cpu_brand, physical_memory FROM system_info;",
      "interval": 3600,
      "description": "System information"
    },
    "uptime": {
      "query": "SELECT days, hours, minutes FROM uptime;",
      "interval": 60,
      "description": "System uptime"
    },
    "kernel_info": {
      "query": "SELECT version, path FROM kernel_info;",
      "interval": 3600,
      "description": "Kernel information"
    },
    "installed_packages": {
      "query": "SELECT name, version FROM deb_packages;",
      "interval": 3600,
      "description": "Installed DEB packages"
    },
    "open_sockets": {
      "query": "SELECT DISTINCT pid, family, protocol, local_address, local_port, remote_address, remote_port, path FROM process_open_sockets WHERE path <> '' AND pid > 0;",
      "interval": 60,
      "description": "Open network sockets"
    },
    "listening_ports": {
      "query": "SELECT pid, port, protocol, path FROM listening_ports;",
      "interval": 60,
      "description": "Listening network ports"
    },
    "users": {
      "query": "SELECT uid, gid, username, description, directory, shell FROM users;",
      "interval": 300,
      "description": "Local user accounts"
    },
    "groups": {
      "query": "SELECT gid, groupname FROM groups;",
      "interval": 300,
      "description": "Local groups"
    },
    "logged_in_users": {
      "query": "SELECT user, host, time FROM logged_in_users;",
      "interval": 60,
      "description": "Currently logged in users"
    },
    "processes": {
      "query": "SELECT pid, name, path, cmdline, uid FROM processes;",
      "interval": 60,
      "description": "Running processes"
    },
    "crontab": {
      "query": "SELECT command, path FROM crontab;",
      "interval": 3600,
      "description": "Crontab entries"
    },
    "ssh_keys": {
      "query": "SELECT uid, path, encrypted FROM user_ssh_keys;",
      "interval": 3600,
      "description": "SSH keys"
    },
    "iptables": {
      "query": "SELECT chain, policy, target, protocol, src_ip, dst_ip FROM iptables;",
      "interval": 300,
      "description": "Firewall rules"
    },
    "file_events": {
      "query": "SELECT * FROM file_events;",
      "interval": 60,
      "description": "File change events"
    },
    "hardware_events": {
      "query": "SELECT * FROM hardware_events;",
      "interval": 60,
      "description": "Hardware change events"
    }
  },

  "decorators": {
    "load": [
      "SELECT uuid AS host_uuid FROM system_info;",
      "SELECT user AS username FROM logged_in_users ORDER BY time DESC LIMIT 1;"
    ]
  },

  "packs": {
    "osquery-monitoring": "/etc/osquery/packs/osquery-monitoring.conf",
    "incident-response": "/etc/osquery/packs/incident-response.conf",
    "vuln-management": "/etc/osquery/packs/vuln-management.conf"
  },

  "file_paths": {
    "configuration": [
      "/etc/passwd",
      "/etc/shadow",
      "/etc/sudoers",
      "/etc/ssh/%%"
    ],
    "binaries": [
      "/usr/bin/%%",
      "/usr/sbin/%%",
      "/bin/%%",
      "/sbin/%%"
    ]
  },

  "exclude_paths": {
    "configuration": [
      "/etc/ssh/ssh_host_%%"
    ]
  }
}
EOF

    # Create compliance pack
    mkdir -p /etc/osquery/packs
    cat << 'EOF' > /etc/osquery/packs/vuln-management.conf
{
  "queries": {
    "kernel_modules": {
      "query": "SELECT name, used_by, status FROM kernel_modules WHERE status = 'Live';",
      "interval": 3600,
      "platform": "linux",
      "description": "Loaded kernel modules"
    },
    "deb_packages_vulnerabilities": {
      "query": "SELECT name, version FROM deb_packages WHERE name IN ('openssl', 'openssh-server', 'bash', 'sudo');",
      "interval": 3600,
      "platform": "linux",
      "description": "Critical packages versions"
    },
    "setuid_binaries": {
      "query": "SELECT path, uid, gid, mode FROM file WHERE path LIKE '/usr/bin/%' AND mode LIKE '4%';",
      "interval": 3600,
      "platform": "linux",
      "description": "Setuid binaries"
    },
    "world_writable_files": {
      "query": "SELECT path FROM file WHERE path LIKE '/etc/%' AND mode LIKE '%7';",
      "interval": 3600,
      "platform": "linux",
      "description": "World-writable files in /etc"
    },
    "shadow_file_integrity": {
      "query": "SELECT path, md5 FROM hash WHERE path = '/etc/shadow';",
      "interval": 300,
      "platform": "linux",
      "description": "Shadow file integrity check"
    }
  }
}
EOF

    # Enable and start osquery
    systemctl enable osqueryd
    systemctl start osqueryd

    log "osquery installation completed"
}

# Install Wazuh agent
install_wazuh() {
    if [ "$INSTALL_WAZUH" != "true" ]; then
        log "Skipping Wazuh installation"
        return
    fi

    log "Installing Wazuh security agent..."

    # Add Wazuh repository
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
    echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | \
        tee /etc/apt/sources.list.d/wazuh.list

    apt-get update

    # Install Wazuh agent
    WAZUH_MANAGER="wazuh-manager.example.com" \
    WAZUH_REGISTRATION_SERVER="wazuh-manager.example.com" \
    apt-get install -y wazuh-agent

    # Configure Wazuh for compliance monitoring
    cat << 'EOF' > /var/ossec/etc/ossec.conf
<ossec_config>
  <client>
    <server>
      <address>wazuh-manager.example.com</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <config-profile>ubuntu, ubuntu22, ubuntu22.04</config-profile>
    <notify_time>10</notify_time>
    <time-reconnect>60</time-reconnect>
    <auto_restart>yes</auto_restart>
  </client>

  <!-- Log collection -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/dpkg.log</location>
  </localfile>

  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/apache2/access.log</location>
  </localfile>

  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/apache2/error.log</location>
  </localfile>

  <localfile>
    <log_format>command</log_format>
    <command>df -P</command>
    <frequency>360</frequency>
  </localfile>

  <localfile>
    <log_format>full_command</log_format>
    <command>netstat -tulpn | sed 's/\([[:alnum:]]\+\)\ \+[[:digit:]]\+\ \+[[:digit:]]\+\ \+\(.*\):\([[:digit:]]*\)\ \+\([0-9\.\:\*]\+\).\+\ \([[:digit:]]*\/[[:alnum:]\-]*\).*/\1 \2 == \3 == \4 \5/' | sort -k 4 -g | sed 's/ == \(.*\) ==/:\1/' | sed 1,2d</command>
    <frequency>360</frequency>
    <alias>netstat listening ports</alias>
  </localfile>

  <!-- File integrity monitoring -->
  <syscheck>
    <disabled>no</disabled>
    <frequency>43200</frequency>
    <scan_on_start>yes</scan_on_start>

    <!-- Directories to monitor -->
    <directories>/etc,/usr/bin,/usr/sbin</directories>
    <directories>/bin,/sbin</directories>
    <directories check_all="yes" realtime="yes">/home</directories>

    <!-- Files to ignore -->
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/random.seed</ignore>
    <ignore>/etc/adjtime</ignore>
    <ignore>/etc/httpd/logs</ignore>
    <ignore>/etc/utmpx</ignore>
    <ignore>/etc/wtmpx</ignore>
    <ignore>/etc/cups/certs</ignore>
    <ignore>/etc/dumpdates</ignore>
    <ignore>/etc/svc/volatile</ignore>

    <!-- Check the file, but never compute the diff -->
    <nodiff>/etc/ssl/private.key</nodiff>

    <skip_nfs>yes</skip_nfs>
    <skip_dev>yes</skip_dev>
    <skip_proc>yes</skip_proc>
    <skip_sys>yes</skip_sys>

    <!-- Nice value for Syscheck process -->
    <process_priority>10</process_priority>

    <!-- Maximum output throughput -->
    <max_eps>100</max_eps>

    <!-- Database synchronization settings -->
    <synchronization>
      <enabled>yes</enabled>
      <interval>5m</interval>
      <max_eps>10</max_eps>
    </synchronization>
  </syscheck>

  <!-- Security Configuration Assessment -->
  <sca>
    <enabled>yes</enabled>
    <scan_on_start>yes</scan_on_start>
    <interval>12h</interval>
    <skip_nfs>yes</skip_nfs>

    <policies>
      <policy>cis_ubuntu22-04.yml</policy>
      <policy>sca_unix_audit.yml</policy>
    </policies>
  </sca>

  <!-- Vulnerability Detection -->
  <vulnerability-detector>
    <enabled>yes</enabled>
    <interval>5m</interval>
    <ignore_time>6h</ignore_time>
    <run_on_start>yes</run_on_start>

    <provider name="canonical">
      <enabled>yes</enabled>
      <os>jammy</os>
      <update_interval>1h</update_interval>
    </provider>
  </vulnerability-detector>

  <!-- Active Response -->
  <active-response>
    <disabled>no</disabled>
    <ca_store>etc/wpk_root.pem</ca_store>
    <ca_verification>yes</ca_verification>
  </active-response>

  <!-- Osquery integration -->
  <wodle name="osquery">
    <disabled>no</disabled>
    <run_daemon>yes</run_daemon>
    <log_path>/var/log/osquery/osqueryd.results.log</log_path>
    <config_path>/etc/osquery/osquery.conf</config_path>
    <add_labels>yes</add_labels>
  </wodle>

  <!-- CIS-CAT integration -->
  <wodle name="cis-cat">
    <disabled>no</disabled>
    <timeout>1800</timeout>
    <interval>1d</interval>
    <scan-on-start>yes</scan-on-start>

    <java_path>wodles/java</java_path>
    <ciscat_path>wodles/ciscat</ciscat_path>
  </wodle>

</ossec_config>
EOF

    # Enable and start Wazuh agent
    systemctl enable wazuh-agent
    systemctl start wazuh-agent

    log "Wazuh installation completed"
}

# Install OpenSCAP for compliance scanning
install_openscap() {
    log "Installing OpenSCAP compliance scanner..."

    # Install OpenSCAP
    apt-get install -y libopenscap8 openscap-utils openscap-scanner

    # Download Ubuntu security guides
    mkdir -p /usr/share/openscap/ssg
    cd /usr/share/openscap/ssg

    # Download SCAP Security Guide for Ubuntu
    wget https://github.com/ComplianceAsCode/content/releases/latest/download/scap-security-guide-0.1.69-oval-5.10.zip -O ssg.zip
    unzip -o ssg.zip
    rm ssg.zip

    # Create compliance scanning script
    cat << 'EOF' > /usr/local/bin/openscap-compliance
#!/bin/bash
# OpenSCAP compliance scanning script

PROFILE="${1:-cis_level2_server}"
OUTPUT_DIR="/var/log/openscap"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

mkdir -p "$OUTPUT_DIR"

# Run OpenSCAP compliance scan
oscap xccdf eval \
    --profile "$PROFILE" \
    --results "${OUTPUT_DIR}/${TIMESTAMP}-results.xml" \
    --report "${OUTPUT_DIR}/${TIMESTAMP}-report.html" \
    --fetch-remote-resources \
    /usr/share/openscap/ssg/ssg-ubuntu2204-xccdf.xml

# Generate OVAL results
oscap oval eval \
    --results "${OUTPUT_DIR}/${TIMESTAMP}-oval-results.xml" \
    --report "${OUTPUT_DIR}/${TIMESTAMP}-oval-report.html" \
    /usr/share/openscap/ssg/ssg-ubuntu2204-oval.xml

# Calculate evidence hash
sha256sum "${OUTPUT_DIR}/${TIMESTAMP}-"* > "${OUTPUT_DIR}/${TIMESTAMP}-evidence.sha256"

echo "Compliance scan complete. Results in ${OUTPUT_DIR}/${TIMESTAMP}-*"
EOF
    chmod +x /usr/local/bin/openscap-compliance

    log "OpenSCAP installation completed"
}

# Install TruffleHog for secrets detection
install_trufflehog() {
    log "Installing TruffleHog secrets scanner..."

    # Download TruffleHog
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

    # Create secrets scanning script
    cat << 'EOF' > /usr/local/bin/trufflehog-scan
#!/bin/bash
# TruffleHog secrets scanning script

TARGET="${1:-.}"
OUTPUT_DIR="/var/log/trufflehog"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

mkdir -p "$OUTPUT_DIR"

# Run TruffleHog scan
trufflehog filesystem "$TARGET" \
    --json \
    --no-update \
    > "${OUTPUT_DIR}/${TIMESTAMP}-secrets.json"

# Parse results and create summary
jq -r '.[] | "\(.Detector): \(.Raw)"' "${OUTPUT_DIR}/${TIMESTAMP}-secrets.json" \
    > "${OUTPUT_DIR}/${TIMESTAMP}-summary.txt"

# Calculate evidence hash
sha256sum "${OUTPUT_DIR}/${TIMESTAMP}-"* > "${OUTPUT_DIR}/${TIMESTAMP}-evidence.sha256"

echo "Secrets scan complete. Results in ${OUTPUT_DIR}/${TIMESTAMP}-*"
EOF
    chmod +x /usr/local/bin/trufflehog-scan

    log "TruffleHog installation completed"
}

# Install gitleaks for additional secrets detection
install_gitleaks() {
    log "Installing gitleaks secrets scanner..."

    # Download and install gitleaks
    wget https://github.com/zricethezav/gitleaks/releases/latest/download/gitleaks_8.18.0_linux_x64.tar.gz
    tar -xzf gitleaks_8.18.0_linux_x64.tar.gz
    mv gitleaks /usr/local/bin/
    rm gitleaks_8.18.0_linux_x64.tar.gz

    # Create gitleaks configuration
    cat << 'EOF' > /etc/gitleaks.toml
title = "Gitleaks Configuration for CMMC Compliance"

[[rules]]
id = "aws-access-key"
description = "AWS Access Key"
regex = '''(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}'''

[[rules]]
id = "aws-secret-key"
description = "AWS Secret Key"
regex = '''(?i)aws(.{0,20})?(?-i)['\"][0-9a-zA-Z\/+]{40}['\"]'''

[[rules]]
id = "github-token"
description = "GitHub Personal Access Token"
regex = '''ghp_[0-9a-zA-Z]{36}'''

[[rules]]
id = "private-key"
description = "Private Key"
regex = '''-----BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY-----'''

[[rules]]
id = "api-key"
description = "Generic API Key"
regex = '''(?i)(api[_\-\s]?key|apikey)(.{0,20})?['\"][0-9a-zA-Z]{32,45}['\"]'''

[allowlist]
paths = [
    "vendor",
    "node_modules",
    ".git"
]
EOF

    # Create scanning script
    cat << 'EOF' > /usr/local/bin/gitleaks-scan
#!/bin/bash
# Gitleaks secrets scanning script

TARGET="${1:-.}"
OUTPUT_DIR="/var/log/gitleaks"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")

mkdir -p "$OUTPUT_DIR"

# Run gitleaks scan
gitleaks detect \
    --source "$TARGET" \
    --config /etc/gitleaks.toml \
    --report-format json \
    --report-path "${OUTPUT_DIR}/${TIMESTAMP}-secrets.json"

# Generate summary
gitleaks detect \
    --source "$TARGET" \
    --config /etc/gitleaks.toml \
    --verbose \
    > "${OUTPUT_DIR}/${TIMESTAMP}-summary.txt" 2>&1

# Calculate evidence hash
sha256sum "${OUTPUT_DIR}/${TIMESTAMP}-"* > "${OUTPUT_DIR}/${TIMESTAMP}-evidence.sha256"

echo "Secrets scan complete. Results in ${OUTPUT_DIR}/${TIMESTAMP}-*"
EOF
    chmod +x /usr/local/bin/gitleaks-scan

    log "gitleaks installation completed"
}

# Generate installation report
generate_report() {
    log "Generating installation report..."

    local report_file="/var/log/security-tools-report.txt"

    cat << EOF > "$report_file"
================================================================================
                    SECURITY TOOLS INSTALLATION REPORT
================================================================================
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Hostname: $(hostname)
================================================================================

INSTALLED TOOLS:
----------------
EOF

    # Check installed tools
    command -v trivy &>/dev/null && echo "✓ Trivy $(trivy --version 2>&1 | head -1)" >> "$report_file"
    command -v grype &>/dev/null && echo "✓ Grype $(grype version 2>&1 | grep Version | cut -d: -f2)" >> "$report_file"
    command -v syft &>/dev/null && echo "✓ Syft $(syft version 2>&1 | grep Version | cut -d: -f2)" >> "$report_file"
    [ "$INSTALL_FALCO" = "true" ] && systemctl is-active falco &>/dev/null && echo "✓ Falco (Active)" >> "$report_file"
    [ "$INSTALL_OSQUERY" = "true" ] && systemctl is-active osqueryd &>/dev/null && echo "✓ osquery (Active)" >> "$report_file"
    [ "$INSTALL_WAZUH" = "true" ] && systemctl is-active wazuh-agent &>/dev/null && echo "✓ Wazuh Agent (Active)" >> "$report_file"
    command -v oscap &>/dev/null && echo "✓ OpenSCAP $(oscap --version 2>&1 | grep Version | cut -d: -f2)" >> "$report_file"
    command -v trufflehog &>/dev/null && echo "✓ TruffleHog" >> "$report_file"
    command -v gitleaks &>/dev/null && echo "✓ gitleaks" >> "$report_file"

    cat << EOF >> "$report_file"

SCANNING SCRIPTS:
-----------------
$(ls -1 /usr/local/bin/*-scan 2>/dev/null | xargs -n1 basename)

CONFIGURATION FILES:
--------------------
$(find /etc -name "*.yaml" -o -name "*.conf" -o -name "*.toml" 2>/dev/null | grep -E "(trivy|grype|falco|osquery|wazuh|gitleaks)" | head -10)

LOG DIRECTORIES:
----------------
/var/log/trivy-scans
/var/log/grype-scans
/var/log/falco
/var/log/osquery
/var/log/openscap
/var/log/trufflehog
/var/log/gitleaks

COMPLIANCE NOTES:
-----------------
- All tools configured for CMMC 2.0 Level 2 compliance
- NIST SP 800-171 controls: 3.14.1 (Flaw Remediation)
- Continuous monitoring enabled where applicable
- Evidence collection automated with SHA-256 hashing
- All scan results stored in JSON format for parsing

================================================================================
                              END OF REPORT
================================================================================
EOF

    # Calculate hash of report
    sha256sum "$report_file" > "${report_file}.sha256"

    log "Installation report generated at $report_file"
}

# Main execution
main() {
    log "Starting security tools installation..."
    log "Configuration: FALCO=$INSTALL_FALCO, OSQUERY=$INSTALL_OSQUERY, WAZUH=$INSTALL_WAZUH"

    # Update package lists
    apt-get update

    # Install common dependencies
    apt-get install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        jq \
        unzip

    # Install security tools
    install_trivy
    install_grype
    install_falco
    install_osquery
    install_wazuh
    install_openscap
    install_trufflehog
    install_gitleaks

    # Generate report
    generate_report

    log "Security tools installation completed successfully!"
}

# Run main function
main "$@"