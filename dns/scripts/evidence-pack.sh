#!/usr/bin/env bash
# Package recent DNS evidence files into a tarball with hashes

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EVIDENCE_DIR="$ROOT_DIR/../compliance/evidence/dns"
TS=$(date +%Y%m%d-%H%M%S)
OUT="/tmp/dns-evidence-${TS}.tar.gz"

if [[ ! -d "$EVIDENCE_DIR" ]]; then
    echo "No evidence directory: $EVIDENCE_DIR" >&2
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cp -a "$EVIDENCE_DIR" "$tmpdir/" 2>/dev/null || true
find "$tmpdir" -type f -print0 | xargs -0 -I{} sha256sum {} > "$tmpdir/hashes.txt"

tar czf "$OUT" -C "$tmpdir" .
echo "Evidence packaged: $OUT"

