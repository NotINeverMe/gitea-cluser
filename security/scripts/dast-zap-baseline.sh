#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

targets=()
[[ -n "${GITEA_URL:-}" ]] && targets+=("$GITEA_URL")
[[ -n "${ATLANTIS_URL:-}" ]] && targets+=("$ATLANTIS_URL")
[[ -n "${DASHBOARD_URL:-}" ]] && targets+=("$DASHBOARD_URL")

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No targets set in security/.env; skipping ZAP baseline"
  exit 0
fi

ZAP_MAX_DURATION=${ZAP_MAX_DURATION:-180}

for url in "${targets[@]}"; do
  safe_name=$(echo "$url" | sed 's#https\?://##; s#[^a-zA-Z0-9_.-]#_#g')
  html="$EVIDENCE_DIR/zap-${safe_name}-$(ts).html"
  json="$EVIDENCE_DIR/zap-${safe_name}-$(ts).json"

  docker run --rm -u "$(id -u):$(id -g)" owasp/zap2docker-stable \
    zap-baseline.py -t "$url" -m 1 -r /tmp/report.html -J /tmp/report.json -d -z "-config api.disablekey=true" \
    -I -T $ZAP_MAX_DURATION || true

  docker run --rm -v "$EVIDENCE_DIR":/out -v /tmp:/tmp alpine:3 \
    sh -lc 'cp /tmp/report.html /out/zap-tmp.html && cp /tmp/report.json /out/zap-tmp.json' || true
  mv -f "$EVIDENCE_DIR/zap-tmp.html" "$html" 2>/dev/null || true
  mv -f "$EVIDENCE_DIR/zap-tmp.json" "$json" 2>/dev/null || true
  echo "ZAP baseline report: $html | $json"
done

