#!/usr/bin/env bash
# Export Namecheap DNS hosts for a domain and write evidence + YAML snapshot
# Requirements: curl, grep, sed, awk

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EVIDENCE_DIR="$ROOT_DIR/../compliance/evidence/dns"
SNAPSHOT_DIR="$ROOT_DIR/snapshots"

load_env() {
    # Load dns/.env if present without leaking values to stdout
    local env_file="$ROOT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
    fi
    : "${NAMECHEAP_API_USER:?Missing NAMECHEAP_API_USER}"
    : "${NAMECHEAP_API_KEY:?Missing NAMECHEAP_API_KEY}"
    : "${SLD:?Missing SLD}"; : "${TLD:?Missing TLD}"
}

main() {
    load_env
    mkdir -p "$EVIDENCE_DIR" "$SNAPSHOT_DIR"

    local client_ip
    if [[ "${NAMECHEAP_API_IP:-auto}" == "auto" ]]; then
        client_ip=$(curl -4 -s https://ifconfig.me)
    else
        client_ip="$NAMECHEAP_API_IP"
    fi

    local ts domain outfile
    ts=$(date +%Y%m%d-%H%M%S)
    domain="${SLD}.${TLD}"
    outfile="$EVIDENCE_DIR/namecheap-getHosts-${domain}-${ts}.xml"

    curl -sS "https://api.namecheap.com/xml.response" \
        --data-urlencode "ApiUser=${NAMECHEAP_API_USER}" \
        --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
        --data-urlencode "UserName=${NAMECHEAP_API_USER}" \
        --data-urlencode "ClientIp=${client_ip}" \
        --data-urlencode "Command=namecheap.domains.dns.getHosts" \
        --data-urlencode "SLD=${SLD}" \
        --data-urlencode "TLD=${TLD}" \
        -o "${outfile}"

    if ! grep -q 'Status="OK"' "${outfile}"; then
        echo "Non-OK response. Inspect: ${outfile}" >&2
        head -n 60 "${outfile}" >&2 || true
        exit 1
    fi

    # Build a simple YAML snapshot from the XML
    local yaml
    yaml="$SNAPSHOT_DIR/${domain}-${ts}.yaml"
    {
        echo "domain: ${domain}"
        # Attempt to carry forward the EmailType present in getHosts response
        local email_type
        email_type=$(grep -m1 '<DomainDNSGetHostsResult ' "${outfile}" | sed -nE 's/.*EmailType="([^"]*)".*/\1/p')
        [[ -n "$email_type" ]] && echo "email_type: ${email_type}"
        echo "records:"
        # shellcheck disable=SC2013
        for line in $(grep '<host ' "${outfile}" | sed 's/ /\x20/g'); do
            line=$(echo -e "$line" | sed 's/\\x20/ /g')
            name=$(sed -nE 's/.* Name="([^"]*)".*/\1/p' <<< "$line")
            type=$(sed -nE 's/.* Type="([^"]*)".*/\1/p' <<< "$line")
            addr=$(sed -nE 's/.* Address="([^"]*)".*/\1/p' <<< "$line")
            ttl=$(sed -nE 's/.* TTL="([^"]*)".*/\1/p' <<< "$line")
            mxp=$(sed -nE 's/.* MXPref="([^"]*)".*/\1/p' <<< "$line")
            echo "  - name: \"${name}\""
            echo "    type: ${type}"
            echo "    address: \"${addr}\""
            [[ -n "$ttl" ]] && echo "    ttl: ${ttl}"
            if [[ "$type" == "MX" && -n "$mxp" ]]; then
                echo "    mx_pref: ${mxp}"
            fi
        done
    } > "$yaml"

    echo "Saved XML: ${outfile}"
    echo "Saved YAML: ${yaml}"
}

main "$@"

