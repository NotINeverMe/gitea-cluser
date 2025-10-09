#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EVIDENCE_DIR="$ROOT_DIR/../compliance/evidence/security"

mkdir -p "$EVIDENCE_DIR"

load_env() {
  local env_file="$ROOT_DIR/.env"
  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
}

ts() { date +%Y%m%d-%H%M%S; }

