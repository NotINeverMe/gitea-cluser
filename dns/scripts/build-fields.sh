#!/usr/bin/env bash
# Translate dns/config/desired.records into Namecheap setHosts fields
# Output: series of HostNameN=..., RecordTypeN=..., AddressN=..., TTLN=..., MXPrefN=...

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RECORDS_FILE="${1:-$ROOT_DIR/config/desired.records}"

if [[ ! -f "$RECORDS_FILE" ]]; then
    echo "Desired records file not found: $RECORDS_FILE" >&2
    exit 1
fi

n=0
while IFS= read -r line; do
    # Skip comments and blank lines
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Expect: name type address ttl [mx_pref]
    name=$(awk '{print $1}' <<< "$line")
    rtype=$(awk '{print $2}' <<< "$line")
    addr=$(awk '{print $3}' <<< "$line")
    ttl=$(awk '{print $4}' <<< "$line")
    pref=$(awk '{print $5}' <<< "$line")

    if [[ -z "$name" || -z "$rtype" || -z "$addr" ]]; then
        echo "Invalid record line (need name type address [ttl [pref]]): $line" >&2
        exit 1
    fi
    n=$((n+1))
    printf 'HostName%d=%s\n' "$n" "$name"
    printf 'RecordType%d=%s\n' "$n" "$rtype"
    printf 'Address%d=%s\n' "$n" "$addr"
    if [[ -n "${ttl:-}" ]]; then
        printf 'TTL%d=%s\n' "$n" "$ttl"
    fi
    if [[ "$rtype" == "MX" && -n "${pref:-}" ]]; then
        printf 'MXPref%d=%s\n' "$n" "$pref"
    fi
done < "$RECORDS_FILE"

