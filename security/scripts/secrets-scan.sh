#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

out="$EVIDENCE_DIR/gitleaks-$(ts).json"

docker run --rm -v "$ROOT_DIR/..":/workspace zricethezav/gitleaks:latest \
  detect --source=/workspace -f json -r /tmp/gitleaks.json || true

docker run --rm -v "$EVIDENCE_DIR":/out -v /tmp:/tmp alpine:3 \
  sh -lc 'cp /tmp/gitleaks.json /out/gitleaks.json' || true

mv -f "$EVIDENCE_DIR/gitleaks.json" "$out" 2>/dev/null || true
echo "Gitleaks report: $out"

