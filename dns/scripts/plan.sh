#!/usr/bin/env bash
# Compare desired.records to live DNS and write a diff to evidence

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EVIDENCE_DIR="$ROOT_DIR/../compliance/evidence/dns"

load_env() {
    local env_file="$ROOT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
    fi
    : "${SLD:?Missing SLD}"; : "${TLD:?Missing TLD}"
}

main() {
    load_env
    mkdir -p "$EVIDENCE_DIR"
    local ts domain xml current_flat desired_flat diff_file
    ts=$(date +%Y%m%d-%H%M%S)
    domain="${SLD}.${TLD}"

    # Ensure we have a fresh XML export
    "$ROOT_DIR/scripts/export.sh" >/dev/null
    xml=$(ls -1t "$EVIDENCE_DIR"/namecheap-getHosts-${domain}-*.xml | head -n1)

    current_flat=$(mktemp)
    desired_flat=$(mktemp)
    trap 'rm -f "$current_flat" "$desired_flat"' EXIT

    "$ROOT_DIR/scripts/flatten.sh" "$xml" > "$current_flat"
    "$ROOT_DIR/scripts/normalize-records.sh" "$ROOT_DIR/config/desired.records" > "$desired_flat"

    diff_file="$EVIDENCE_DIR/plan-${domain}-${ts}.diff"
    if ! diff -u "$current_flat" "$desired_flat" > "$diff_file" 2>&1; then
        echo "Diff saved: $diff_file"
    else
        echo "No differences. Diff saved: $diff_file"
    fi
}

main "$@"

