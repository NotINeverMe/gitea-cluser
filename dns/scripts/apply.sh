#!/usr/bin/env bash
# Apply desired.records to Namecheap using scripts/dns-update-namecheap.sh
# WARNING: setHosts replaces ALL records. Use plan/apply-dry first.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPDATE_SCRIPT="$ROOT_DIR/../scripts/dns-update-namecheap.sh"

load_env() {
    local env_file="$ROOT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
    fi
    : "${NAMECHEAP_API_USER:?Missing NAMECHEAP_API_USER}"
    : "${NAMECHEAP_API_KEY:?Missing NAMECHEAP_API_KEY}"
    : "${SLD:?Missing SLD}"; : "${TLD:?Missing TLD}"
    TTL_DEFAULT="${TTL_DEFAULT:-300}"
}

main() {
    load_env

    # Compute client IP
    if [[ "${NAMECHEAP_API_IP:-auto}" == "auto" ]]; then
        export NAMECHEAP_API_IP=$(curl -4 -s https://ifconfig.me)
    fi

    # Build fields
    mapfile -t fields < <("$ROOT_DIR/scripts/build-fields.sh")
    if [[ ${#fields[@]} -eq 0 ]]; then
        echo "No records found in config/desired.records" >&2
        exit 1
    fi

    # Prepare args
    args=("${fields[@]}")

    if [[ "${DRY_RUN:-}" == "1" ]]; then
        echo "[DRY-RUN] scripts/dns-update-namecheap.sh would be called with ${#args[@]} fields"
        CONFIRM_OVERWRITE=1 SLD="$SLD" TLD="$TLD" TTL="$TTL_DEFAULT" \
        NAMECHEAP_API_USER="$NAMECHEAP_API_USER" NAMECHEAP_API_KEY="$NAMECHEAP_API_KEY" \
        NAMECHEAP_API_IP="${NAMECHEAP_API_IP}" EMAIL_TYPE="${EMAIL_TYPE:-}" \
        "$UPDATE_SCRIPT" "${args[@]}"
        exit 0
    fi

    # Require explicit confirmation in the environment (Makefile enforces too)
    if [[ "${CONFIRM_OVERWRITE:-}" != "1" ]]; then
        echo "Refusing to run: set CONFIRM_OVERWRITE=1 to proceed" >&2
        exit 1
    fi

    # Call updater
    SLD="$SLD" TLD="$TLD" TTL="$TTL_DEFAULT" \
    NAMECHEAP_API_USER="$NAMECHEAP_API_USER" NAMECHEAP_API_KEY="$NAMECHEAP_API_KEY" \
    NAMECHEAP_API_IP="${NAMECHEAP_API_IP}" EMAIL_TYPE="${EMAIL_TYPE:-}" \
    "$UPDATE_SCRIPT" "${args[@]}"
}

main "$@"

