#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

out="$EVIDENCE_DIR/bandit-$(ts).json"

# Scan Python code under dashboard/ if present
if [[ ! -d "$ROOT_DIR/../dashboard" ]]; then
  echo "No dashboard/ directory; skipping bandit"
  exit 0
fi

docker run --rm -v "$ROOT_DIR/..":/src -w /src python:3 \
  bash -lc "pip install --no-cache-dir bandit && bandit -r dashboard -f json -o /tmp/bandit.json" || true

mkdir -p "$EVIDENCE_DIR"
docker run --rm -v "$EVIDENCE_DIR":/out -v /tmp:/tmp alpine:3 \
  sh -lc 'cp /tmp/bandit.json /out/bandit.json' || true

mv -f "$EVIDENCE_DIR/bandit.json" "$out" 2>/dev/null || true
echo "Bandit report: $out"

