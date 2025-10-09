#!/usr/bin/env bash
# Normalize a desired.records file into sorted comparable lines
# Output format: TYPE name address ttl [mx_pref]

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RECORDS_FILE="${1:-$ROOT_DIR/config/desired.records}"

if [[ ! -f "$RECORDS_FILE" ]]; then
    echo "Desired records file not found: $RECORDS_FILE" >&2
    exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    name=$(awk '{print $1}' <<< "$line")
    rtype=$(awk '{print $2}' <<< "$line")
    addr=$(awk '{print $3}' <<< "$line")
    ttl=$(awk '{print $4}' <<< "$line")
    pref=$(awk '{print $5}' <<< "$line")
    if [[ "$rtype" == "MX" && -n "$pref" ]]; then
        echo "$rtype $name $addr $ttl $pref" >> "$tmp"
    else
        echo "$rtype $name $addr $ttl" >> "$tmp"
    fi
done < "$RECORDS_FILE"

sort -u "$tmp"

