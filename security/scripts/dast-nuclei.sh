#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

targets_str="${NUCLEI_TARGETS:-}"
if [[ -z "$targets_str" ]]; then
  [[ -n "${GITEA_URL:-}" ]] && targets_str+="$GITEA_URL "
  [[ -n "${ATLANTIS_URL:-}" ]] && targets_str+="$ATLANTIS_URL "
  [[ -n "${DASHBOARD_URL:-}" ]] && targets_str+="$DASHBOARD_URL "
fi

if [[ -z "$targets_str" ]]; then
  echo "No targets set in security/.env; skipping nuclei"
  exit 0
fi

out="$EVIDENCE_DIR/nuclei-$(ts).json"
docker run --rm -i projectdiscovery/nuclei:latest -json -no-interact -silent 2>/dev/null <<EOF > "$out" || true
$(for u in $targets_str; do echo "$u"; done)
EOF

echo "Nuclei report: $out"

