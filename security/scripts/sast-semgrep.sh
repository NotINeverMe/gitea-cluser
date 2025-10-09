#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

out="$EVIDENCE_DIR/semgrep-$(ts).json"

docker run --rm -v "$ROOT_DIR/..":/src -w /src semgrep/semgrep:latest \
  semgrep --error --config p/ci --json -o /tmp/semgrep.json || true

mkdir -p "$EVIDENCE_DIR"
docker run --rm -v "$EVIDENCE_DIR":/out -v /tmp:/tmp alpine:3 \
  sh -lc 'cp /tmp/semgrep.json /out/semgrep.json' || true

mv -f "$EVIDENCE_DIR/semgrep.json" "$out" 2>/dev/null || true
echo "Semgrep report: $out"

