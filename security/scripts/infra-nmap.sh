#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

targets_str="${INFRA_TARGETS:-}"
if [[ -z "$targets_str" ]]; then
  [[ -n "${GITEA_URL:-}" ]] && targets_str+="$(echo "$GITEA_URL" | sed -nE 's#https?://([^/]+)/?.*#\1#p') "
  [[ -n "${ATLANTIS_URL:-}" ]] && targets_str+="$(echo "$ATLANTIS_URL" | sed -nE 's#https?://([^/]+)/?.*#\1#p') "
  [[ -n "${DASHBOARD_URL:-}" ]] && targets_str+="$(echo "$DASHBOARD_URL" | sed -nE 's#https?://([^/]+)/?.*#\1#p') "
fi

if [[ -z "$targets_str" ]]; then
  echo "No infra targets; set INFRA_TARGETS or *_URL in security/.env"
  exit 0
fi

NMAP_FULL=${NMAP_FULL:-0}
NMAP_PORTS=${NMAP_PORTS:-}
NMAP_VULN=${NMAP_VULN:-0}

ports_flag=()
if [[ "$NMAP_FULL" == "1" ]]; then
  ports_flag=(-p-)
elif [[ -n "$NMAP_PORTS" ]]; then
  ports_flag=(-p "$NMAP_PORTS")
fi

scripts_flag=()
[[ "$NMAP_VULN" == "1" ]] && scripts_flag=(--script vuln)

for tgt in $targets_str; do
  safe=$(echo "$tgt" | sed 's#[^a-zA-Z0-9_.-]#_#g')
  xml="$EVIDENCE_DIR/nmap-${safe}-$(ts).xml"
  gnmap="$EVIDENCE_DIR/nmap-${safe}-$(ts).gnmap"
  docker run --rm --net=host instrumentisto/nmap \
    nmap -sS -sV -Pn "${ports_flag[@]}" "${scripts_flag[@]}" -oX - "$tgt" | tee "$xml" >/dev/null
  # Produce a greppable output via local conversion pass
  docker run --rm instrumentisto/nmap sh -lc "echo '$(ts)' >/dev/null" >/dev/null 2>&1 || true
  # As a fallback, run a second lightweight scan to emit gnmap (fast)
  docker run --rm --net=host instrumentisto/nmap \
    nmap -Pn -oG - "$tgt" | tee "$gnmap" >/dev/null
  echo "Nmap reports: $xml | $gnmap"
done

