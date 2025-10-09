#!/usr/bin/env bash
# Flatten a Namecheap getHosts XML file into sorted comparable lines
# Output format: TYPE name address ttl [mx_pref]

set -euo pipefail

xml_file="$1"
if [[ -z "${xml_file}" || ! -f "${xml_file}" ]]; then
    echo "Usage: $0 <getHosts.xml>" >&2
    exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Each <host .../> on a single line (already is), parse attributes
grep '<host ' "$xml_file" | while IFS= read -r line; do
    name=$(sed -nE 's/.* Name="([^"]*)".*/\1/p' <<< "$line")
    type=$(sed -nE 's/.* Type="([^"]*)".*/\1/p' <<< "$line")
    addr=$(sed -nE 's/.* Address="([^"]*)".*/\1/p' <<< "$line")
    ttl=$(sed -nE 's/.* TTL="([^"]*)".*/\1/p' <<< "$line")
    pref=$(sed -nE 's/.* MXPref="([^"]*)".*/\1/p' <<< "$line")
    if [[ "$type" == "MX" && -n "$pref" ]]; then
        echo "$type $name $addr $ttl $pref" >> "$tmp"
    else
        echo "$type $name $addr $ttl" >> "$tmp"
    fi
done

sort -u "$tmp"

