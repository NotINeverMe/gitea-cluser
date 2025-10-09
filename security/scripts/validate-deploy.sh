#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

targets=()
[[ -n "${GITEA_URL:-}" ]] && targets+=("$GITEA_URL")
[[ -n "${ATLANTIS_URL:-}" ]] && targets+=("$ATLANTIS_URL")
[[ -n "${DASHBOARD_URL:-}" ]] && targets+=("$DASHBOARD_URL")

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No targets set in security/.env; skipping deployment validation"
  exit 0
fi

check_headers() {
  local url="$1"; shift
  local file="$1"; shift
  curl -sk -D - "$url" -o /dev/null > "$file" || true
}

tls_summary() {
  local host port
  host="$1"; port=443
  echo "TLS summary for $host";
  echo | openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null | \
    openssl x509 -noout -issuer -subject -dates || true
}

for url in "${targets[@]}"; do
  safe_name=$(echo "$url" | sed 's#https\?://##; s#[^a-zA-Z0-9_.-]#_#g')
  out="$EVIDENCE_DIR/validate-${safe_name}-$(ts).md"
  {
    echo "# Deployment Validation: $url"
    echo
    echo "## HTTP Response"
    status=$(curl -sk -o /dev/null -w '%{http_code}' "$url")
    echo "Status: $status"
    echo
    echo "## Security Headers"
    hdrtmp=$(mktemp); check_headers "$url" "$hdrtmp"
    printf '%s\n' "$(grep -iE '^(Strict-Transport-Security|Content-Security-Policy|X-Content-Type-Options|X-Frame-Options|Referrer-Policy|Permissions-Policy):' "$hdrtmp" || true)"
    echo
    echo "## TLS"
    host=$(echo "$url" | sed -nE 's#https?://([^/]+)/?.*#\1#p')
    tls_summary "$host"
  } > "$out"
  echo "Validation report: $out"
done

