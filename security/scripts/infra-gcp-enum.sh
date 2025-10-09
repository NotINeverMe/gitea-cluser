#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud not available; skipping GCP infra enumeration"
  exit 0
fi

TS=$(ts)
json="$EVIDENCE_DIR/gcp-enum-$TS.json"
md="$EVIDENCE_DIR/gcp-enum-$TS.md"

project=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "unset")}

# Collect core resources to JSON bundle
instances=$(gcloud compute instances list --format=json || echo '[]')
firewalls=$(gcloud compute firewall-rules list --format=json || echo '[]')
addresses=$(gcloud compute addresses list --format=json || echo '[]')

printf '{"project":"%s","instances":%s,"firewalls":%s,"addresses":%s}\n' "$project" "$instances" "$firewalls" "$addresses" > "$json"

# Write a readable summary focusing on open ports to 0.0.0.0/0
{
  echo "# GCP Infra Enumeration"
  echo "Project: $project"
  echo
  echo "## Public Firewall Rules (0.0.0.0/0)"
  echo
  echo "$firewalls" | jq -r '.[] | select(.sourceRanges[]? == "0.0.0.0/0") | "- \(.name): allow \(.allowed[]?.IPProtocol) \(.allowed[]?.ports // [])"' 2>/dev/null || true
  echo
  echo "## External Addresses"
  echo "$addresses" | jq -r '.[] | "- \(.name): \(.address) (\(.status))"' 2>/dev/null || true
  echo
  echo "## Instances (name, zone, external IPs)"
  echo "$instances" | jq -r '.[] | "- \(.name) [\(.zone | split("/")[-1])]: " + ( .networkInterfaces[]?.accessConfigs[]?.natIP // "none")' 2>/dev/null || true
} > "$md"

echo "GCP enumeration: $json | $md"

