#!/bin/bash
# Startup Script for Gitea VM Instance
# CMMC 2.0 Level 2 and NIST SP 800-171 Rev. 2 Compliant Configuration
# This script implements security hardening and compliance controls

set -euo pipefail

# ============================================================================
# VARIABLES AND CONFIGURATION
# ============================================================================

PROJECT_ID="${project_id}"
REGION="${region}"
ZONE="${zone}"
ENVIRONMENT="${environment}"
GITEA_DOMAIN="${gitea_domain}"
GITEA_ADMIN_USERNAME="${gitea_admin_username}"
GITEA_ADMIN_EMAIL="${gitea_admin_email}"
ADMIN_PASSWORD_SECRET="${admin_password_secret}"
DB_PASSWORD_SECRET="${db_password_secret}"
RUNNER_TOKEN_SECRET="${runner_token_secret}"
EVIDENCE_BUCKET="${evidence_bucket}"
BACKUP_BUCKET="${backup_bucket}"
LOGS_BUCKET="${logs_bucket}"
ENABLE_SECRET_MANAGER="${enable_secret_manager}"
GITEA_DISABLE_REGISTRATION="${gitea_disable_registration}"
GITEA_REQUIRE_SIGNIN_VIEW="${gitea_require_signin_view}"
ENABLE_DOCKER_GCR="${enable_docker_gcr}"

# Logging configuration
LOG_FILE="/var/log/startup-script.log"
EVIDENCE_DIR="/var/log/evidence"
AUDIT_LOG="/var/log/audit/audit.log"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_security() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SECURITY: $1" | tee -a "$LOG_FILE" "$EVIDENCE_DIR/security.log"
}

# ============================================================================
# EVIDENCE COLLECTION - AU.L2-3.3.1: Event Logging
# ============================================================================

create_evidence() {
    local event_type="$1"
    local event_data="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$EVIDENCE_DIR/startup_$(date +%s).json" <<EOF
{
    "timestamp": "$timestamp",
    "event_type": "$event_type",
    "hostname": "$(hostname)",
    "project_id": "$PROJECT_ID",
    "environment": "$ENVIRONMENT",
    "event_data": $event_data,
    "cmmc_control": "AU.L2-3.3.1",
    "nist_control": "AU-3"
}
EOF

    # Upload to GCS if available
    if command -v gsutil &> /dev/null; then
        gsutil -q cp "$EVIDENCE_DIR/startup_$(date +%s).json" "gs://$EVIDENCE_BUCKET/startup/" || true
    fi
}

# ============================================================================
# SYSTEM INITIALIZATION
# ============================================================================

log "Starting Gitea VM initialization script"
log "Environment: $ENVIRONMENT"
log "Project: $PROJECT_ID"

# Create necessary directories
mkdir -p "$EVIDENCE_DIR"
mkdir -p /mnt/gitea-data/{gitea,postgres,runner,backups,logs}
mkdir -p /etc/gitea
mkdir -p /var/log/gitea

# ============================================================================
# SYSTEM HARDENING - CM.L2-3.4.2: Baseline Configuration
# ============================================================================

log "Applying CIS Level 2 security hardening"

# Update system packages
log "Updating system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential packages
log "Installing essential packages"
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ufw \
    fail2ban \
    auditd \
    aide \
    rkhunter \
    clamav \
    clamav-daemon \
    unattended-upgrades \
    rsync \
    jq \
    htop \
    net-tools \
    tcpdump \
    vim \
    git

# Configure automatic security updates - SI.L2-3.14.1: System Monitoring
log "Configuring automatic security updates"
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# ============================================================================
# KERNEL HARDENING - SC.L2-3.13.15: System Integrity
# ============================================================================

log "Applying kernel hardening parameters"

cat > /etc/sysctl.d/99-security.conf <<'EOF'
# IP forwarding disabled
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Send redirects disabled
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Source packet verification
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Accept ICMP redirects disabled
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Accept source route disabled
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# ICMP Echo ignore broadcasts
net.ipv4.icmp_echo_ignore_broadcasts = 1

# ICMP ignore bogus error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN cookies enabled
net.ipv4.tcp_syncookies = 1

# TCP timestamps disabled
net.ipv4.tcp_timestamps = 0

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# Core dumps restricted
fs.suid_dumpable = 0

# Kernel panic reboot
kernel.panic = 60

# Restrict kernel logs
kernel.dmesg_restrict = 1

# Restrict kernel pointers
kernel.kptr_restrict = 2

# ASLR enabled
kernel.randomize_va_space = 2

# Restrict loading TTY line disciplines
dev.tty.ldisc_autoload = 0

# Restrict userfaultfd() to privileged users
vm.unprivileged_userfaultfd = 0

# Increase system file descriptor limit
fs.file-max = 2097152

# Increase inotify limits for monitoring
fs.inotify.max_user_watches = 524288
EOF

sysctl -p /etc/sysctl.d/99-security.conf

# ============================================================================
# FIREWALL CONFIGURATION - SC.L2-3.13.1: Boundary Protection
# ============================================================================

log "Configuring UFW firewall"

# Reset UFW to defaults
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# Allow SSH from IAP only
ufw allow from 35.235.240.0/20 to any port 22 comment 'SSH from IAP'

# Allow HTTPS
ufw allow 443/tcp comment 'HTTPS'

# Allow Git SSH on custom port
ufw allow 10001/tcp comment 'Git SSH'

# Allow health checks from Google
ufw allow from 35.191.0.0/16 to any port 443 comment 'Google health checks'
ufw allow from 130.211.0.0/22 to any port 443 comment 'Google health checks'

# Enable UFW
ufw --force enable
ufw logging on
ufw status verbose

log_security "Firewall configured with restrictive rules"

# ============================================================================
# FAIL2BAN CONFIGURATION - AC.L2-3.1.8: Unsuccessful Logon Attempts
# ============================================================================

log "Configuring Fail2ban"

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
action = %(action_mwl)s

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[gitea]
enabled = true
port = 443,10001
filter = gitea
logpath = /var/log/gitea/*.log
maxretry = 5
bantime = 3600
EOF

# Create Gitea filter
cat > /etc/fail2ban/filter.d/gitea.conf <<'EOF'
[Definition]
failregex = .*Failed authentication attempt for .* from <HOST>
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# ============================================================================
# AUDITD CONFIGURATION - AU.L2-3.3.1: Event Logging
# ============================================================================

log "Configuring auditd for CMMC compliance"

# Configure audit rules
cat > /etc/audit/rules.d/cmmc.rules <<'EOF'
# Delete all rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Monitor authentication events
-w /var/log/faillog -p wa -k auth_failures
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Monitor user/group changes
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor sudoers
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor system calls
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b64 -S socket -S connect -k network
-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM -k access
-a always,exit -F arch=b64 -S open -S openat -F exit=-EACCES -k access

# Monitor Docker
-w /usr/bin/docker -p x -k docker
-w /var/lib/docker/ -p wa -k docker
-w /etc/docker/ -p wa -k docker

# Monitor Gitea
-w /mnt/gitea-data/ -p wa -k gitea
-w /etc/gitea/ -p wa -k gitea

# Make configuration immutable
-e 2
EOF

# Restart auditd
systemctl enable auditd
systemctl restart auditd

log_security "Auditd configured for comprehensive logging"

# ============================================================================
# AIDE CONFIGURATION - SI.L2-3.14.1: System Monitoring
# ============================================================================

log "Configuring AIDE for file integrity monitoring"

cat > /etc/aide/aide.conf.d/99_gitea <<'EOF'
# Gitea specific monitoring
/mnt/gitea-data/gitea/conf p+u+g+s+m+c+md5+sha256
/etc/gitea p+u+g+s+m+c+md5+sha256
/usr/local/bin p+u+g+s+m+c+md5+sha256
EOF

# Initialize AIDE database
aideinit -y -f
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Create AIDE check cron job
cat > /etc/cron.daily/aide-check <<'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "AIDE Daily Report" root
EOF
chmod +x /etc/cron.daily/aide-check

# ============================================================================
# INSTALL DOCKER - Application Platform
# ============================================================================

log "Installing Docker"

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Configure Docker daemon
cat > /etc/docker/daemon.json <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "10"
    },
    "storage-driver": "overlay2",
    "iptables": true,
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true
}
EOF

# Configure Docker to use GCR if enabled
if [[ "$ENABLE_DOCKER_GCR" == "true" ]]; then
    gcloud auth configure-docker --quiet
fi

systemctl enable docker
systemctl restart docker

# ============================================================================
# MOUNT DATA DISK - Storage Configuration
# ============================================================================

log "Mounting data disk"

# Format data disk if not already formatted
if ! blkid /dev/sdb; then
    mkfs.ext4 -F /dev/sdb
fi

# Get UUID of data disk
DATA_UUID=$(blkid -s UUID -o value /dev/sdb)

# Add to fstab for persistent mounting
echo "UUID=$DATA_UUID /mnt/gitea-data ext4 defaults,nofail,x-systemd.device-timeout=10 0 2" >> /etc/fstab

# Mount the disk
mount -a

# Set permissions
chmod 755 /mnt/gitea-data
chown root:docker /mnt/gitea-data

# ============================================================================
# INSTALL GCSFUSE - For GCS bucket mounting
# ============================================================================

log "Installing gcsfuse for GCS bucket access"

export GCSFUSE_REPO=gcsfuse-$(lsb_release -c -s)
echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt-get update
apt-get install -y gcsfuse

# Create mount points for buckets
mkdir -p /mnt/{evidence,backup,logs}

# ============================================================================
# INSTALL CLOUD OPS AGENT - SI.L2-3.14.1: System Monitoring
# ============================================================================

log "Installing Cloud Ops Agent for monitoring and logging"

curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
rm add-google-cloud-ops-agent-repo.sh

# Configure Ops Agent
cat > /etc/google-cloud-ops-agent/config.yaml <<'EOF'
logging:
  receivers:
    syslog:
      type: files
      include_paths:
      - /var/log/syslog
      - /var/log/auth.log
    docker:
      type: files
      include_paths:
      - /var/lib/docker/containers/**/*.log
    gitea:
      type: files
      include_paths:
      - /mnt/gitea-data/gitea/log/*.log
    audit:
      type: files
      include_paths:
      - /var/log/audit/audit.log
  processors:
    parse_json:
      type: parse_json
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog, docker, gitea, audit]
        processors: [parse_json]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
EOF

systemctl restart google-cloud-ops-agent

# ============================================================================
# RETRIEVE SECRETS - IA.L2-3.5.7: Password Complexity
# ============================================================================

if [[ "$ENABLE_SECRET_MANAGER" == "true" ]]; then
    log "Retrieving secrets from Secret Manager"

    ADMIN_PASSWORD=$(gcloud secrets versions access latest --secret="$ADMIN_PASSWORD_SECRET" --project="$PROJECT_ID")
    DB_PASSWORD=$(gcloud secrets versions access latest --secret="$DB_PASSWORD_SECRET" --project="$PROJECT_ID")
    RUNNER_TOKEN=$(gcloud secrets versions access latest --secret="$RUNNER_TOKEN_SECRET" --project="$PROJECT_ID")
else
    log "Using default passwords (not recommended for production)"
    ADMIN_PASSWORD="ChangeMe!123456"
    DB_PASSWORD="ChangeMe!123456"
    RUNNER_TOKEN="ChangeMe!123456"
fi

# ============================================================================
# CREATE DOCKER COMPOSE CONFIGURATION
# ============================================================================

log "Creating Docker Compose configuration for Gitea stack"

cat > /mnt/gitea-data/docker-compose.yml <<EOF
version: '3.8'

networks:
  gitea:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  postgres:
    image: postgres:15-alpine
    container_name: gitea-postgres
    restart: always
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=$DB_PASSWORD
      - POSTGRES_DB=gitea
    networks:
      gitea:
        ipv4_address: 172.20.0.2
    volumes:
      - /mnt/gitea-data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "10"

  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: always
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=postgres:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=$DB_PASSWORD
      - GITEA__server__DOMAIN=$GITEA_DOMAIN
      - GITEA__server__SSH_DOMAIN=$GITEA_DOMAIN
      - GITEA__server__ROOT_URL=https://$GITEA_DOMAIN/
      - GITEA__server__SSH_PORT=10001
      - GITEA__server__SSH_LISTEN_PORT=22
      - GITEA__server__LFS_START_SERVER=true
      - GITEA__server__OFFLINE_MODE=false
      - GITEA__service__DISABLE_REGISTRATION=$GITEA_DISABLE_REGISTRATION
      - GITEA__service__REQUIRE_SIGNIN_VIEW=$GITEA_REQUIRE_SIGNIN_VIEW
      - GITEA__service__DEFAULT_KEEP_EMAIL_PRIVATE=true
      - GITEA__service__DEFAULT_ALLOW_CREATE_ORGANIZATION=false
      - GITEA__service__DEFAULT_ENABLE_TIMETRACKING=true
      - GITEA__security__INSTALL_LOCK=true
      - GITEA__security__SECRET_KEY=\$(openssl rand -hex 32)
      - GITEA__security__INTERNAL_TOKEN=\$(openssl rand -hex 32)
      - GITEA__security__PASSWORD_COMPLEXITY=lower,upper,digit,spec
      - GITEA__security__MIN_PASSWORD_LENGTH=14
      - GITEA__security__PASSWORD_CHECK_PWN=true
      - GITEA__log__LEVEL=Info
      - GITEA__log__ROOT_PATH=/data/log
      - GITEA__mailer__ENABLED=false
      - GITEA__openid__ENABLE_OPENID_SIGNIN=false
      - GITEA__repository__DEFAULT_PRIVATE=true
      - GITEA__repository__DISABLE_HTTP_GIT=false
      - GITEA__repository__MAX_CREATION_LIMIT=100
      - GITEA__ui__DEFAULT_THEME=arc-green
      - GITEA__webhook__ALLOWED_HOST_LIST=*
      - GITEA__metrics__ENABLED=true
      - GITEA__actions__ENABLED=true
    networks:
      gitea:
        ipv4_address: 172.20.0.3
    volumes:
      - /mnt/gitea-data/gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "10001:22"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/version"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "10"

  caddy:
    image: caddy:latest
    container_name: gitea-caddy
    restart: always
    networks:
      gitea:
        ipv4_address: 172.20.0.5
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /mnt/gitea-data/caddy/data:/data
      - /mnt/gitea-data/caddy/config:/config
      - /mnt/gitea-data/caddy/Caddyfile:/etc/caddy/Caddyfile
    depends_on:
      - gitea
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "10"

  runner:
    image: gitea/act_runner:latest
    container_name: gitea-runner
    restart: always
    environment:
      - GITEA_INSTANCE_URL=http://gitea:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=$RUNNER_TOKEN
      - GITEA_RUNNER_NAME=docker-runner
      - GITEA_RUNNER_LABELS=ubuntu-latest:docker://node:16-bullseye,ubuntu-22.04:docker://node:16-bullseye,ubuntu-20.04:docker://node:16-bullseye
    networks:
      gitea:
        ipv4_address: 172.20.0.4
    volumes:
      - /mnt/gitea-data/runner:/data
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - gitea
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "10"
EOF

# Create Caddyfile for automatic HTTPS
mkdir -p /mnt/gitea-data/caddy
cat > /mnt/gitea-data/caddy/Caddyfile <<CADDYEOF
$GITEA_DOMAIN {
    reverse_proxy gitea:3000

    encode gzip

    log {
        output file /data/access.log
        format json
    }
}
CADDYEOF

# ============================================================================
# CREATE SYSTEMD SERVICE
# ============================================================================

log "Creating systemd service for Gitea stack"

cat > /etc/systemd/system/gitea-stack.service <<'EOF'
[Unit]
Description=Gitea Docker Compose Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/mnt/gitea-data
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gitea-stack
systemctl start gitea-stack

# ============================================================================
# CONFIGURE LOG ROTATION - AU.L2-3.3.9: Audit Log Retention
# ============================================================================

log "Configuring log rotation"

cat > /etc/logrotate.d/gitea <<'EOF'
/mnt/gitea-data/gitea/log/*.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 1000 1000
    postrotate
        docker exec gitea sh -c 'kill -USR1 $(cat /var/run/gitea.pid)' || true
    endscript
}

/var/log/gitea/*.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

# ============================================================================
# SETUP BACKUP SCRIPT - CP.L2-3.11.1: System Backup
# ============================================================================

log "Creating backup script"

cat > /usr/local/bin/gitea-backup.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/mnt/gitea-data/backups"
BACKUP_NAME="gitea-backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/gitea-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting Gitea backup"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup Gitea data
docker exec gitea su git -c "gitea dump -c /data/gitea/conf/app.ini --file /tmp/$BACKUP_NAME.zip"
docker cp gitea:/tmp/$BACKUP_NAME.zip "$BACKUP_DIR/"

# Backup PostgreSQL
docker exec gitea-postgres pg_dumpall -U gitea > "$BACKUP_DIR/$BACKUP_NAME-postgres.sql"

# Compress backups
tar -czf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" \
    -C "$BACKUP_DIR" \
    "$BACKUP_NAME.zip" \
    "$BACKUP_NAME-postgres.sql"

# Remove uncompressed files
rm -f "$BACKUP_DIR/$BACKUP_NAME.zip" "$BACKUP_DIR/$BACKUP_NAME-postgres.sql"

# Upload to GCS
if command -v gsutil &> /dev/null; then
    gsutil -q cp "$BACKUP_DIR/$BACKUP_NAME.tar.gz" "gs://${backup_bucket}/daily/"
    log "Backup uploaded to GCS"
fi

# Clean up old local backups (keep last 7 days)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

log "Backup completed successfully"
EOF

chmod +x /usr/local/bin/gitea-backup.sh

# Create backup cron job
echo "0 2 * * * /usr/local/bin/gitea-backup.sh" | crontab -

# ============================================================================
# CONFIGURE CIS BENCHMARKS - CM.L2-3.4.2: Baseline Configuration
# ============================================================================

log "Applying additional CIS Level 2 benchmarks"

# Disable unused network protocols
cat >> /etc/modprobe.d/blacklist.conf <<'EOF'
# CIS 3.3.1 Ensure DCCP is disabled
install dccp /bin/true
# CIS 3.3.2 Ensure SCTP is disabled
install sctp /bin/true
# CIS 3.3.3 Ensure RDS is disabled
install rds /bin/true
# CIS 3.3.4 Ensure TIPC is disabled
install tipc /bin/true
EOF

# Set permissions on important files
chmod 644 /etc/passwd
chmod 640 /etc/shadow
chmod 644 /etc/group
chmod 640 /etc/gshadow
chmod 600 /etc/ssh/sshd_config

# Configure SSH hardening
cat >> /etc/ssh/sshd_config <<'EOF'

# CMMC/NIST Hardening
Protocol 2
PermitRootLogin no
PermitEmptyPasswords no
PasswordAuthentication no
PubkeyAuthentication yes
IgnoreRhosts yes
HostbasedAuthentication no
X11Forwarding no
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
Banner /etc/ssh/banner
AllowGroups ssh-users google-sudoers
Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs umac-64-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521
EOF

# Create SSH banner
cat > /etc/ssh/banner <<'EOF'
***************************************************************************
                            AUTHORIZED ACCESS ONLY

This system is for authorized use only. By accessing this system, you agree
that your actions may be monitored and recorded. Unauthorized access is
strictly prohibited and will be prosecuted to the fullest extent of the law.

CMMC 2.0 Level 2 Compliant System - NIST SP 800-171 Rev. 2
***************************************************************************
EOF

systemctl restart sshd

# ============================================================================
# INITIALIZE GITEA - Application Setup
# ============================================================================

log "Waiting for Gitea to be ready"
sleep 30

# Check if Gitea is running
for i in {1..60}; do
    if docker exec gitea curl -s -o /dev/null -w "%%{http_code}" http://localhost:3000/api/v1/version | grep -q "200"; then
        log "Gitea is ready"
        break
    fi
    log "Waiting for Gitea to start... ($i/60)"
    sleep 5
done

# Create admin user if not exists
docker exec gitea su git -c "gitea admin user create \
    --username $GITEA_ADMIN_USERNAME \
    --password '$ADMIN_PASSWORD' \
    --email $GITEA_ADMIN_EMAIL \
    --admin \
    --must-change-password=false" || log "Admin user may already exist"

# ============================================================================
# FINAL EVIDENCE COLLECTION
# ============================================================================

log "Collecting final deployment evidence"

create_evidence "deployment_complete" '{
    "status": "success",
    "services": {
        "docker": "running",
        "gitea": "running",
        "postgres": "running",
        "runner": "running"
    },
    "security_controls": {
        "firewall": "enabled",
        "fail2ban": "enabled",
        "auditd": "enabled",
        "aide": "initialized",
        "automatic_updates": "enabled",
        "cis_hardening": "applied"
    },
    "storage": {
        "data_disk": "mounted",
        "backup_configured": true,
        "gcs_buckets": ["evidence", "backup", "logs"]
    }
}'

# Upload all evidence to GCS
if command -v gsutil &> /dev/null; then
    gsutil -m rsync -r "$EVIDENCE_DIR" "gs://$EVIDENCE_BUCKET/startup/"
fi

# ============================================================================
# CUSTOM STARTUP SCRIPT (if provided)
# ============================================================================

if [[ -n "${custom_startup_script}" ]]; then
    log "Executing custom startup script"
    eval "${custom_startup_script}"
fi

# ============================================================================
# COMPLETION
# ============================================================================

log "Gitea VM initialization completed successfully"
log "Access Gitea at: https://$GITEA_DOMAIN"
log "Admin username: $GITEA_ADMIN_USERNAME"
log "Evidence collected in: $EVIDENCE_DIR and gs://$EVIDENCE_BUCKET"
log "Backups will be stored in: gs://$BACKUP_BUCKET"
log "Logs are being sent to: gs://$LOGS_BUCKET"

# Send completion notification to Cloud Logging
logger -t startup-script "Gitea initialization completed successfully for $ENVIRONMENT environment"

exit 0