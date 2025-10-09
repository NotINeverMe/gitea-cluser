# Terraform Backend Configuration
#
# IMPORTANT: This file contains environment-specific values.
# For new environments, generate from backend.tf.template
#
# To generate for a new environment:
#   sed "s|__STATE_BUCKET_NAME__|$(cd bootstrap && terraform output -raw state_bucket_name)|g" \\
#     backend.tf.template > backend.tf
#
# Current Configuration: Production Environment
# ==============================================================================

terraform {
  backend "gcs" {
    # State bucket created by bootstrap
    bucket = "cui-gitea-prod-gitea-tfstate-f5f2e413"

    # Prefix for this environment (allows multi-environment in same bucket)
    prefix = "terraform/state"

    # Encryption: Handled by bucket's default KMS key
    # State locking: Automatic with GCS versioning
    # Authentication: Uses Application Default Credentials (gcloud auth)
  }
}

# ==============================================================================
# NOTES
# ==============================================================================
#
# - This backend configuration is for the PRODUCTION environment
# - Bucket name is from bootstrap terraform output
# - For dev/staging, use different prefixes or separate buckets
# - See backend.tf.template for detailed multi-environment setup
#
# To migrate state: terraform init -migrate-state
# To reconfigure: terraform init -reconfigure
# ==============================================================================
