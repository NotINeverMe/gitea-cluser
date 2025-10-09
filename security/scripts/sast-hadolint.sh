#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

out="$EVIDENCE_DIR/hadolint-$(ts).json"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Find Dockerfiles
mapfile -t dockerfiles < <(find "$ROOT_DIR/.." -type f -iname 'Dockerfile*' | sort || true)
if [[ ${#dockerfiles[@]} -eq 0 ]]; then
  echo "No Dockerfiles found; skipping hadolint"
  exit 0
fi

docker run --rm -i hadolint/hadolint < /dev/null >/dev/null 2>&1 || true

{
  echo '['
  sep=""
  for f in "${dockerfiles[@]}"; do
    echo "$sep" | sed 's/.*/&/' >/dev/null
    docker run --rm -v "$f:/work/Dockerfile:ro" hadolint/hadolint hadolint -f json /work/Dockerfile || true
    sep="," # naive separator for concatenation at packaging time
  done
  echo ']'
} > "$out" 2>/dev/null || true

echo "Hadolint report: $out"

