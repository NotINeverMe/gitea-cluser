#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

targets=()
[[ -n "${GITEA_URL:-}" ]] && targets+=("$GITEA_URL")
[[ -n "${ATLANTIS_URL:-}" ]] && targets+=("$ATLANTIS_URL")
[[ -n "${DASHBOARD_URL:-}" ]] && targets+=("$DASHBOARD_URL")

targets_str="${INFRA_TARGETS:-}"
for t in $targets_str; do
  [[ "$t" =~ ^https?:// ]] && targets+=("$t") || targets+=("https://$t")
done

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No infra targets; set INFRA_TARGETS or *_URL in security/.env"
  exit 0
fi

TESTSSL_OPTS=${TESTSSL_OPTS:---quiet}

for url in "${targets[@]}"; do
  host=$(echo "$url" | sed -nE 's#https?://([^/]+)/?.*#\1#p')
  safe=$(echo "$host" | sed 's#[^a-zA-Z0-9_.-]#_#g')
  json="$EVIDENCE_DIR/testssl-${safe}-$(ts).json"
  txt="$EVIDENCE_DIR/testssl-${safe}-$(ts).txt"
  docker run --rm drwetter/testssl.sh $TESTSSL_OPTS --jsonfile /out/out.json "$host" 2>&1 | tee "$txt" >/dev/null || true
  # The container writes the JSON inside; re-run mounting out to capture JSON
  docker run --rm -v "$EVIDENCE_DIR":/out drwetter/testssl.sh $TESTSSL_OPTS --jsonfile /out/testssl-tmp.json "$host" >/dev/null 2>&1 || true
  mv -f "$EVIDENCE_DIR/testssl-tmp.json" "$json" 2>/dev/null || true
  echo "testssl reports: $txt | $json"
done

