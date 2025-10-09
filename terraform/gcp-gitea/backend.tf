# Terraform Backend Configuration (GCS)
#
# Backend parameters (bucket, prefix) are provided at init time to avoid
# hard-coding environment-specific values in source control. Example usage:
#   terraform init \
#     -backend-config="bucket=your-bootstrap-state-bucket" \
#     -backend-config="prefix=envs/prod"
#
# See terraform/gcp-gitea/README.md for bootstrap instructions.

terraform {
  backend "gcs" {}
}
