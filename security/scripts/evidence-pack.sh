#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"

TS=$(ts)
OUT="/tmp/security-evidence-${TS}.tar.gz"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cp -a "$EVIDENCE_DIR" "$tmpdir/" 2>/dev/null || true
find "$tmpdir" -type f -print0 | xargs -0 -I{} sha256sum {} > "$tmpdir/hashes.txt"

tar czf "$OUT" -C "$tmpdir" .
echo "Evidence packaged: $OUT"

