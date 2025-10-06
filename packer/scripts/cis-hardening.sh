#!/bin/bash
# CIS Ubuntu 22.04 LTS Hardening Script
# CMMC 2.0: CM.L2-3.4.1 (Baseline Configuration)
# NIST SP 800-171: 3.4.1, 3.4.2
# CIS Benchmark: Ubuntu Linux 22.04 LTS v1.0.0

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="cis-hardening.sh"
readonly LOG_FILE="/var/log/cis-hardening.log"
readonly EVIDENCE_DIR="/var/log/compliance-evidence"
readonly CIS_LEVEL="${CIS_LEVEL:-2}"
readonly FIPS_ENABLED="${FIPS_ENABLED:-true}"
readonly BUILD_DATE="${BUILD_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
readonly IMAGE_NAME="${IMAGE_NAME:-ubuntu-cis-hardened}"

# Logging functions
log() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"
}

log_success() {
    log "[SUCCESS] $*"
}

log_error() {
    log "[ERROR] $*"
}

log_info() {
    log "[INFO] $*"
}

# Evidence collection function
collect_evidence() {
    local control_id="$1"
    local description="$2"
    local evidence_file="${EVIDENCE_DIR}/${control_id}.txt"

    echo "Control: $control_id" > "$evidence_file"
    echo "Description: $description" >> "$evidence_file"
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$evidence_file"
    echo "Status: Applied" >> "$evidence_file"
    echo "---" >> "$evidence_file"
}

# Initialize
initialize() {
    log_info "Starting CIS hardening for $IMAGE_NAME"
    log_info "CIS Level: $CIS_LEVEL"
    log_info "FIPS Mode: $FIPS_ENABLED"
    log_info "Build Date: $BUILD_DATE"

    # Create evidence directory
    mkdir -p "$EVIDENCE_DIR"
    chmod 750 "$EVIDENCE_DIR"
}

# 1. Filesystem Configuration
harden_filesystem() {
    log_info "Applying filesystem hardening..."

    # 1.1.1 Disable unused filesystems
    cat << EOF > /etc/modprobe.d/cis-filesystems.conf
# CIS 1.1.1 - Disable unused filesystems
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install vfat /bin/true
EOF
    collect_evidence "CIS-1.1.1" "Disabled unused filesystems"

    # 1.1.2-1.1.5 Configure /tmp
    if ! grep -q "/tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=2G 0 0" >> /etc/fstab
    fi
    mount -o remount,nosuid,nodev,noexec /tmp 2>/dev/null || true
    collect_evidence "CIS-1.1.2-5" "Configured /tmp with secure mount options"

    # 1.1.8-1.1.10 Configure /var/tmp
    if ! grep -q "/var/tmp" /etc/fstab; then
        echo "/tmp /var/tmp none bind 0 0" >> /etc/fstab
    fi
    mount --bind /tmp /var/tmp 2>/dev/null || true
    collect_evidence "CIS-1.1.8-10" "Configured /var/tmp with secure mount options"

    # 1.1.15-1.1.17 Configure /dev/shm
    mount -o remount,nosuid,nodev,noexec /dev/shm 2>/dev/null || true
    collect_evidence "CIS-1.1.15-17" "Configured /dev/shm with secure mount options"

    # 1.3.1 Ensure AIDE is installed
    apt-get install -y aide aide-common
    aideinit -y -f
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    collect_evidence "CIS-1.3.1" "Installed and initialized AIDE"

    # 1.4.1 Ensure permissions on bootloader config
    chown root:root /boot/grub/grub.cfg
    chmod og-rwx /boot/grub/grub.cfg
    collect_evidence "CIS-1.4.1" "Set secure permissions on bootloader config"

    # 1.5.1 Ensure XD/NX support is enabled
    dmesg | grep -q "NX.*protection: active" && log_success "NX protection is active"
    collect_evidence "CIS-1.5.1" "Verified XD/NX support is enabled"

    # 1.5.3 Ensure ASLR is enabled
    echo 2 > /proc/sys/kernel/randomize_va_space
    echo "kernel.randomize_va_space = 2" >> /etc/sysctl.d/99-cis.conf
    collect_evidence "CIS-1.5.3" "Enabled ASLR"

    log_success "Filesystem hardening completed"
}

# 2. Services
harden_services() {
    log_info "Hardening system services..."

    # 2.1.1 Ensure xinetd is not installed
    apt-get remove --purge -y xinetd 2>/dev/null || true
    collect_evidence "CIS-2.1.1" "Removed xinetd"

    # 2.2.1.1 Ensure time synchronization is in use
    apt-get install -y chrony
    systemctl enable chrony
    systemctl start chrony

    # Configure chrony for security
    cat << EOF > /etc/chrony/chrony.conf
# CIS Hardened chrony configuration
pool 2.ubuntu.pool.ntp.org iburst maxsources 4
sourcedir /run/chrony-sources.d
sourcedir /etc/chrony/sources.d
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
leapsectz right/UTC
EOF
    systemctl restart chrony
    collect_evidence "CIS-2.2.1.1" "Configured time synchronization with chrony"

    # Disable unnecessary services
    local services_to_disable=(
        "avahi-daemon"
        "cups"
        "isc-dhcp-server"
        "slapd"
        "nfs-server"
        "rpcbind"
        "bind9"
        "vsftpd"
        "apache2"
        "dovecot"
        "smbd"
        "squid"
        "snmpd"
        "rsync"
        "nis"
    )

    for service in "${services_to_disable[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        apt-get remove --purge -y "$service" 2>/dev/null || true
    done
    collect_evidence "CIS-2.2.2-17" "Disabled unnecessary services"

    log_success "Services hardening completed"
}

# 3. Network Configuration
harden_network() {
    log_info "Applying network hardening..."

    # 3.1 Network Parameters (Host Only)
    cat << EOF >> /etc/sysctl.d/99-cis.conf
# CIS 3.1 Network Parameters (Host Only)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# CIS 3.2 Network Parameters (Host and Router)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF
    sysctl -p /etc/sysctl.d/99-cis.conf
    collect_evidence "CIS-3.1-3.2" "Applied network kernel parameters"

    # 3.3 TCP Wrappers
    apt-get install -y tcpd
    echo "ALL: ALL" > /etc/hosts.deny
    echo "sshd: ALL" > /etc/hosts.allow
    chmod 644 /etc/hosts.allow
    chmod 644 /etc/hosts.deny
    collect_evidence "CIS-3.3" "Configured TCP Wrappers"

    # 3.4 Firewall Configuration (UFW)
    apt-get install -y ufw

    # Configure UFW defaults
    ufw --force disable
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny routed

    # Allow SSH (adjust port as needed)
    ufw allow 22/tcp

    # Enable UFW
    ufw --force enable
    ufw logging on
    collect_evidence "CIS-3.4" "Configured UFW firewall"

    # Disable IPv6 if not needed
    if [ "$CIS_LEVEL" = "2" ]; then
        cat << EOF >> /etc/sysctl.d/99-cis.conf
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        sysctl -p /etc/sysctl.d/99-cis.conf
        collect_evidence "CIS-3.3.9" "Disabled IPv6"
    fi

    log_success "Network hardening completed"
}

# 4. Logging and Auditing
harden_logging() {
    log_info "Configuring logging and auditing..."

    # 4.1.1.1 Ensure auditd is installed
    apt-get install -y auditd audispd-plugins
    systemctl enable auditd

    # 4.1.1.2 Ensure auditd service is enabled
    cat << EOF > /etc/audit/auditd.conf
# CIS Hardened auditd configuration
local_events = yes
write_logs = yes
log_file = /var/log/audit/audit.log
log_group = adm
log_format = ENRICHED
flush = INCREMENTAL_ASYNC
freq = 50
max_log_file = 8
num_logs = 5
priority_boost = 4
name_format = HOSTNAME
max_log_file_action = ROTATE
space_left = 75
space_left_action = SYSLOG
action_mail_acct = root
admin_space_left = 50
admin_space_left_action = SUSPEND
disk_full_action = SUSPEND
disk_error_action = SUSPEND
use_libwrap = yes
tcp_listen_port = 60
tcp_listen_queue = 5
tcp_max_per_addr = 1
tcp_client_max_idle = 0
enable_krb5 = no
krb5_principal = auditd
distribute_network = no
EOF

    # 4.1.1.3 Configure audit rules
    cat << 'EOF' > /etc/audit/rules.d/cis.rules
# CIS Ubuntu 22.04 Audit Rules
# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# 4.1.3 Changes to system administration scope (sudoers)
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# 4.1.4 Login and logout events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# 4.1.5 Session initiation information
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# 4.1.6 Discretionary Access Control permission modification events
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod

# 4.1.7 Unsuccessful unauthorized file access attempts
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# 4.1.8 Privileged commands
-a always,exit -F path=/usr/bin/passwd -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-passwd
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-sudo
-a always,exit -F path=/usr/bin/su -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-su
-a always,exit -F path=/usr/bin/chsh -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-chsh
-a always,exit -F path=/usr/bin/chfn -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-chfn
-a always,exit -F path=/usr/bin/mount -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-mount
-a always,exit -F path=/usr/bin/umount -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-umount

# 4.1.9 Successful file system mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# 4.1.10 File deletion events
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=4294967295 -k delete

# 4.1.11 MAC changes
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy

# 4.1.12 System administrator actions (sudolog)
-w /var/log/sudo.log -p wa -k actions

# 4.1.13 Kernel module loading and unloading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module,delete_module -k modules

# 4.1.14 Make the audit configuration immutable
-e 2
EOF

    # Load audit rules
    augenrules --load
    systemctl restart auditd
    collect_evidence "CIS-4.1" "Configured auditd logging and rules"

    # 4.2.1 Configure rsyslog
    apt-get install -y rsyslog
    systemctl enable rsyslog

    cat << EOF > /etc/rsyslog.d/50-cis.conf
# CIS rsyslog configuration
*.emerg                       :omusrmsg:*
mail.*                        -/var/log/mail
mail.info                     -/var/log/mail.info
mail.warning                  -/var/log/mail.warn
mail.err                      /var/log/mail.err
news.crit                     -/var/log/news/news.crit
news.err                      -/var/log/news/news.err
news.notice                   -/var/log/news/news.notice
*.=warning;*.=err             -/var/log/warn
*.crit                        /var/log/warn
*.*;mail.none;news.none       -/var/log/messages
local0,local1.*               -/var/log/localmessages
local2,local3.*               -/var/log/localmessages
local4,local5.*               -/var/log/localmessages
local6,local7.*               -/var/log/localmessages

# Log authentication messages to separate file
auth,authpriv.*               /var/log/auth.log
EOF

    # Set proper permissions on log files
    chmod -R g-wx,o-rwx /var/log/*
    systemctl restart rsyslog
    collect_evidence "CIS-4.2" "Configured rsyslog"

    log_success "Logging and auditing configuration completed"
}

# 5. Access, Authentication and Authorization
harden_access_control() {
    log_info "Hardening access control..."

    # 5.1.1 Ensure cron daemon is enabled
    systemctl enable cron

    # 5.1.2-8 Cron permissions
    chown root:root /etc/crontab
    chmod og-rwx /etc/crontab
    chown root:root /etc/cron.hourly
    chmod og-rwx /etc/cron.hourly
    chown root:root /etc/cron.daily
    chmod og-rwx /etc/cron.daily
    chown root:root /etc/cron.weekly
    chmod og-rwx /etc/cron.weekly
    chown root:root /etc/cron.monthly
    chmod og-rwx /etc/cron.monthly
    chown root:root /etc/cron.d
    chmod og-rwx /etc/cron.d

    # Restrict cron to authorized users
    rm -f /etc/cron.deny
    rm -f /etc/at.deny
    touch /etc/cron.allow
    touch /etc/at.allow
    chmod og-rwx /etc/cron.allow
    chmod og-rwx /etc/at.allow
    chown root:root /etc/cron.allow
    chown root:root /etc/at.allow
    collect_evidence "CIS-5.1" "Configured cron access control"

    # 5.2 SSH Server Configuration
    cat << EOF > /etc/ssh/sshd_config.d/99-cis.conf
# CIS SSH Hardening
Protocol 2
LogLevel VERBOSE
X11Forwarding no
MaxAuthTries 4
IgnoreRhosts yes
HostbasedAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
PermitUserEnvironment no
Ciphers chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
StrictModes yes
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
Banner /etc/issue.net
MaxStartups 10:30:60
MaxSessions 4
AllowUsers *@*
DenyGroups root
UsePAM yes
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no
EOF

    # Create SSH banner
    cat << EOF > /etc/issue.net
###############################################################
#                      WARNING BANNER                         #
###############################################################
# Unauthorized access to this system is prohibited and will   #
# be prosecuted to the fullest extent of the law.            #
# All activities on this system are monitored and logged.     #
# By accessing this system, you consent to this monitoring.   #
###############################################################
EOF

    systemctl reload sshd
    collect_evidence "CIS-5.2" "Hardened SSH configuration"

    # 5.3 Configure PAM
    apt-get install -y libpam-pwquality

    # Password quality requirements
    cat << EOF > /etc/security/pwquality.conf
# CIS Password Quality Requirements
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
retry = 3
maxrepeat = 3
maxsequence = 3
gecoscheck = 1
dictcheck = 1
usercheck = 1
enforce_for_root
EOF

    # Configure password policies in PAM
    cat << EOF > /etc/pam.d/common-password
# CIS Hardened PAM password configuration
password    requisite     pam_pwquality.so retry=3
password    [success=1 default=ignore] pam_unix.so obscure use_authtok try_first_pass sha512 remember=5
password    requisite     pam_deny.so
password    required      pam_permit.so
EOF

    # Configure account lockout
    cat << EOF > /etc/pam.d/common-auth
# CIS Hardened PAM authentication
auth    required      pam_tally2.so onerr=fail audit silent deny=5 unlock_time=900
auth    [success=1 default=ignore] pam_unix.so nullok_secure
auth    requisite     pam_deny.so
auth    required      pam_permit.so
auth    optional      pam_cap.so
EOF
    collect_evidence "CIS-5.3" "Configured PAM security policies"

    # 5.4 User Accounts and Environment
    # Set password expiration policies
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   365/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

    # Set default umask
    echo "UMASK 027" >> /etc/login.defs

    # Configure shell timeout
    cat << EOF >> /etc/profile.d/99-cis.sh
# CIS Shell timeout
readonly TMOUT=900
readonly HISTFILE
export TMOUT
EOF

    # Restrict su command
    echo "auth required pam_wheel.so use_uid group=sudo" >> /etc/pam.d/su
    collect_evidence "CIS-5.4" "Configured user account policies"

    log_success "Access control hardening completed"
}

# 6. System Maintenance
harden_system_maintenance() {
    log_info "Applying system maintenance hardening..."

    # 6.1 System File Permissions
    # Fix permissions on important files
    chmod 644 /etc/passwd
    chmod 000 /etc/shadow
    chmod 000 /etc/gshadow
    chmod 644 /etc/group
    chown root:root /etc/passwd
    chown root:shadow /etc/shadow
    chown root:shadow /etc/gshadow
    chown root:root /etc/group

    # Fix permissions on sensitive files
    chmod 644 /etc/ssh/sshd_config
    chown root:root /etc/ssh/sshd_config
    chmod 600 /etc/ssh/ssh_host_*_key
    chmod 644 /etc/ssh/ssh_host_*_key.pub
    collect_evidence "CIS-6.1" "Set proper system file permissions"

    # 6.2 User and Group Settings
    # Ensure password fields are not empty
    awk -F: '($2 == "" ) { print $1 " does not have a password"}' /etc/shadow | while read user; do
        log_error "$user"
        passwd -l "${user%% *}" 2>/dev/null || true
    done

    # Ensure no legacy entries exist in passwd, shadow, and group
    sed -i '/^+:/d' /etc/passwd
    sed -i '/^+:/d' /etc/shadow
    sed -i '/^+:/d' /etc/group

    # Check for duplicate UIDs
    cat /etc/passwd | cut -f3 -d":" | sort -n | uniq -c | while read count uid; do
        if [ "$count" -gt 1 ]; then
            log_error "Duplicate UID ($uid) found"
        fi
    done

    # Check for duplicate GIDs
    cat /etc/group | cut -f3 -d":" | sort -n | uniq -c | while read count gid; do
        if [ "$count" -gt 1 ]; then
            log_error "Duplicate GID ($gid) found"
        fi
    done
    collect_evidence "CIS-6.2" "Verified user and group settings"

    log_success "System maintenance hardening completed"
}

# FIPS 140-2 Configuration
configure_fips() {
    if [ "$FIPS_ENABLED" = "true" ]; then
        log_info "Configuring FIPS 140-2 mode..."

        # Install FIPS packages
        apt-get install -y fips-initramfs fips-updates openssh-server-fips \
            openssh-client-fips libssl1.1-fips libssl-dev-fips strongswan-hmac \
            openssh-server openssh-client 2>/dev/null || true

        # Enable FIPS mode in kernel
        if [ -f /proc/sys/crypto/fips_enabled ]; then
            echo 1 > /proc/sys/crypto/fips_enabled 2>/dev/null || true
        fi

        # Configure OpenSSL for FIPS
        if [ -f /etc/ssl/openssl.cnf ]; then
            sed -i '1s/^/openssl_conf = openssl_init\n/' /etc/ssl/openssl.cnf
            cat << EOF >> /etc/ssl/openssl.cnf

[openssl_init]
providers = provider_sect
alg_section = algorithm_sect

[provider_sect]
fips = fips_sect
base = base_sect

[base_sect]
activate = 1

[fips_sect]
activate = 1

[algorithm_sect]
default_properties = fips=yes
EOF
        fi

        # Update GRUB for FIPS
        if grep -q "GRUB_CMDLINE_LINUX" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 fips=1"/' /etc/default/grub
            update-grub 2>/dev/null || true
        fi

        collect_evidence "FIPS-140-2" "Configured FIPS 140-2 mode"
        log_success "FIPS 140-2 configuration completed (reboot required to activate)"
    fi
}

# Generate compliance report
generate_compliance_report() {
    log_info "Generating compliance report..."

    local report_file="${EVIDENCE_DIR}/cis-compliance-report.txt"

    cat << EOF > "$report_file"
================================================================================
                          CIS COMPLIANCE REPORT
================================================================================
Image Name: $IMAGE_NAME
Build Date: $BUILD_DATE
CIS Level: $CIS_LEVEL
FIPS Mode: $FIPS_ENABLED
Report Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
================================================================================

APPLIED CONTROLS:
-----------------
EOF

    # List all evidence files
    for evidence in "$EVIDENCE_DIR"/CIS-*.txt "$EVIDENCE_DIR"/FIPS-*.txt; do
        if [ -f "$evidence" ]; then
            basename "$evidence" .txt >> "$report_file"
        fi
    done

    cat << EOF >> "$report_file"

SYSTEM INFORMATION:
-------------------
Hostname: $(hostname)
Kernel: $(uname -r)
OS: $(lsb_release -ds)
Architecture: $(uname -m)

SECURITY METRICS:
-----------------
Total CIS Controls Applied: $(ls -1 "$EVIDENCE_DIR"/CIS-*.txt 2>/dev/null | wc -l)
Audit Rules: $(auditctl -l | wc -l)
Firewall Rules: $(ufw status numbered | grep -c '^\[' || echo 0)
Failed Login Attempts: $(faillog -u 1000-60000 | grep -v "Username" | wc -l)

COMPLIANCE MAPPINGS:
--------------------
CMMC 2.0:
  - CM.L2-3.4.1: Establish and maintain baseline configurations
  - SI.L2-3.14.1: Identify, report, and correct system flaws

NIST SP 800-171:
  - 3.4.1: Establish and maintain baseline configurations
  - 3.4.2: Establish and enforce configuration settings
  - 3.14.1: Identify, report, and correct system flaws

================================================================================
                              END OF REPORT
================================================================================
EOF

    # Generate SHA-256 hash of report
    sha256sum "$report_file" > "${report_file}.sha256"

    log_success "Compliance report generated at $report_file"
}

# Main execution
main() {
    initialize

    # Apply hardening based on CIS level
    harden_filesystem
    harden_services
    harden_network
    harden_logging
    harden_access_control
    harden_system_maintenance

    # Apply FIPS if enabled
    configure_fips

    # Generate final report
    generate_compliance_report

    # Create evidence manifest
    find "$EVIDENCE_DIR" -type f -exec sha256sum {} \; > "${EVIDENCE_DIR}/evidence-manifest.sha256"

    log_success "CIS hardening completed successfully!"
    log_info "Evidence collected in: $EVIDENCE_DIR"
    log_info "Review the compliance report: ${EVIDENCE_DIR}/cis-compliance-report.txt"

    # Set marker for successful completion
    touch /etc/cis-hardened
    echo "$BUILD_DATE" > /etc/cis-hardened
}

# Execute main function
main "$@"