#!/usr/bin/env bash
# Namecheap DNS updater (setHosts)
#
# WARNING: namecheap.domains.dns.setHosts REPLACES all host records for the domain.
# Only run when you intend to fully manage the host set or when targeting a
# delegated subzone. As a safeguard, this script refuses to run unless
# CONFIRM_OVERWRITE=1 is set in the environment.
#
# Usage examples:
#   # Single host (A record) — REPLACES ALL HOSTS
#   CONFIRM_OVERWRITE=1 \
#   NAMECHEAP_API_USER=xxxx NAMECHEAP_API_KEY=yyyy NAMECHEAP_API_IP=203.0.113.10 \
#   SLD=cui-secure TLD=us TTL=300 \
#   ./scripts/dns-update-namecheap.sh \
#     HostName1=gitea RecordType1=A Address1=198.51.100.42 TTL1=300
#
#   # Multiple hosts in one call
#   CONFIRM_OVERWRITE=1 SLD=cui-secure TLD=us \
#   NAMECHEAP_API_USER=xxxx NAMECHEAP_API_KEY=yyyy NAMECHEAP_API_IP=203.0.113.10 \
#   ./scripts/dns-update-namecheap.sh \
#     HostName1=gitea    RecordType1=A     Address1=198.51.100.42 TTL1=300 \
#     HostName2=atlantis RecordType2=CNAME Address2=lb.example.net TTL2=300 \
#     HostName3=dashboard RecordType3=CNAME Address3=lb.example.net TTL3=300
#
#   # Dry-run (print curl command only)
#   DRY_RUN=1 CONFIRM_OVERWRITE=1 ... ./scripts/dns-update-namecheap.sh HostName1=...
#
# Inputs (env):
#   NAMECHEAP_API_USER, NAMECHEAP_API_KEY, NAMECHEAP_API_IP
#   SLD, TLD, TTL (optional default 300)
#
# Evidence:
#   Writes raw API response to /tmp/namecheap-dns-YYYYmmdd-HHMMSS.xml

set -euo pipefail

usage() {
    cat <<EOF
Usage: CONFIRM_OVERWRITE=1 SLD=<sld> TLD=<tld> [TTL=300] \
       NAMECHEAP_API_USER=<u> NAMECHEAP_API_KEY=<k> NAMECHEAP_API_IP=<ip> \
       $0 HostName1=<h> RecordType1=<A|CNAME|TXT|MX|AAAA> Address1=<addr> [TTL1=<ttl>] [HostName2=... ...]

Note: This replaces ALL host records for <SLD>.<TLD>. Provide the full desired set.
EOF
}

require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "Missing required env: $var" >&2
        exit 1
    fi
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    if [[ "${CONFIRM_OVERWRITE:-}" != "1" ]]; then
        echo "Refusing to run: CONFIRM_OVERWRITE=1 not set (setHosts replaces ALL hosts)" >&2
        exit 1
    fi

    require_env NAMECHEAP_API_USER
    require_env NAMECHEAP_API_KEY
    require_env NAMECHEAP_API_IP
    require_env SLD
    require_env TLD

    local ttl_default
    ttl_default="${TTL:-300}"

    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    # Build host fields from key=value args
    local -a fields=()
    local have_hostname=0
    for kv in "$@"; do
        if [[ "$kv" != *=* ]]; then
            echo "Invalid arg (expected key=value): $kv" >&2
            exit 1
        fi
        local key="${kv%%=*}"
        local val="${kv#*=}"
        if [[ ! "$key" =~ ^(HostName|RecordType|Address|TTL|MXPref)[0-9]+$ ]];
        then
            echo "Ignoring unsupported key: $key" >&2
            continue
        fi
        if [[ "$key" =~ ^HostName[0-9]+$ ]]; then
            have_hostname=1
        fi
        fields+=("--data-urlencode" "$key=$val")
    done

    if [[ $have_hostname -eq 0 ]]; then
        echo "No HostNameN=... provided. Nothing to update." >&2
        exit 1
    fi

    local ts out_file
    ts=$(date +%Y%m%d-%H%M%S)
    out_file="/tmp/namecheap-dns-${ts}.xml"

    # Base parameters
    local -a base=(
        "--data-urlencode" "ApiUser=${NAMECHEAP_API_USER}"
        "--data-urlencode" "ApiKey=${NAMECHEAP_API_KEY}"
        "--data-urlencode" "UserName=${NAMECHEAP_API_USER}"
        "--data-urlencode" "ClientIp=${NAMECHEAP_API_IP}"
        "--data-urlencode" "Command=namecheap.domains.dns.setHosts"
        "--data-urlencode" "SLD=${SLD}"
        "--data-urlencode" "TLD=${TLD}"
    )

    # Optional email routing mode, e.g., EMAIL_TYPE=MX or NONE
    if [[ -n "${EMAIL_TYPE:-}" ]]; then
        base+=("--data-urlencode" "EmailType=${EMAIL_TYPE}")
    fi

    # If user didn't specify TTLN for a given N, Namecheap defaults are applied.
    # You can enforce a default by passing TTLN explicitly in arguments.

    if [[ "${DRY_RUN:-}" == "1" ]]; then
        echo "[DRY-RUN] Would execute:"
        printf 'curl "https://api.namecheap.com/xml.response" %q ' "${base[@]}" "${fields[@]}"
        echo
        exit 0
    fi

    echo "Updating Namecheap hosts for ${SLD}.${TLD} (response -> ${out_file})"
    set +e
    curl -sS "https://api.namecheap.com/xml.response" \
        "${base[@]}" \
        "${fields[@]}" \
        -o "${out_file}"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        echo "Curl failed with code $rc" >&2
        exit $rc
    fi

    if grep -q 'Status="OK"' "${out_file}"; then
        echo "Success: Namecheap update accepted."
    else
        echo "Warning: Non-OK response. Inspect ${out_file}" >&2
        head -n 50 "${out_file}" || true
        exit 1
    fi
}

main "$@"
