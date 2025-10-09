#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/common.sh"
load_env

tf_dir="$ROOT_DIR/../terraform"
if [[ ! -d "$tf_dir" ]]; then
  echo "No terraform/ directory; skipping infra terraform scans"
  exit 0
fi

echo "Running Checkov..."
docker run --rm -v "$ROOT_DIR/..":/tf bridgecrew/checkov \
  -d /tf/terraform --framework terraform --output json > "$EVIDENCE_DIR/checkov-$(ts).json" || true

echo "Running tfsec..."
docker run --rm -v "$ROOT_DIR/..":/src aquasec/tfsec \
  /src/terraform --format json > "$EVIDENCE_DIR/tfsec-$(ts).json" || true

echo "Running Terrascan..."
docker run --rm -v "$ROOT_DIR/..":/src tenable/terrascan \
  scan -i terraform -t gcp -d /src/terraform -o json > "$EVIDENCE_DIR/terrascan-$(ts).json" || true

echo "Terraform security scans saved under $EVIDENCE_DIR"

