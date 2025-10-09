#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

out="$EVIDENCE_DIR/trivy-fs-$(ts).json"

docker run --rm -v "$ROOT_DIR/..":/workspace aquasec/trivy:latest \
  fs --security-checks vuln,secret,config --format json --timeout 5m /workspace \
  > "$out" || true

echo "Trivy FS report: $out"

