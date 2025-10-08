# Bootstrap Outputs

output "tfstate_bucket" {
  description = "GCS bucket name for Terraform state"
  value       = google_storage_bucket.tfstate.name
}

output "config_bucket" {
  description = "GCS bucket name for configuration storage"
  value       = google_storage_bucket.config.name
}

output "audit_bucket" {
  description = "GCS bucket name for audit logs"
  value       = google_storage_bucket.audit.name
}

output "kms_keyring_id" {
  description = "KMS keyring ID"
  value       = google_kms_key_ring.gitea.id
}

output "tfstate_kms_key_id" {
  description = "KMS key ID for Terraform state encryption"
  value       = google_kms_crypto_key.tfstate.id
}

output "config_kms_key_id" {
  description = "KMS key ID for configuration encryption"
  value       = google_kms_crypto_key.config.id
}

output "audit_kms_key_id" {
  description = "KMS key ID for audit log encryption"
  value       = google_kms_crypto_key.audit.id
}

output "backend_config" {
  description = "Backend configuration for main Terraform"
  value = {
    bucket = google_storage_bucket.tfstate.name
    prefix = "terraform/state"
  }
}

output "next_steps" {
  description = "Next steps after bootstrap"
  value = <<-EOT

    ✅ Bootstrap Complete!

    1. Configure backend in main Terraform:
       cd ..
       cat > backend.tf <<EOF
       terraform {
         backend "gcs" {
           bucket = "${google_storage_bucket.tfstate.name}"
           prefix = "terraform/state"
         }
       }
       EOF

    2. Initialize main Terraform with backend:
       terraform init -backend-config="bucket=${google_storage_bucket.tfstate.name}"

    3. Upload terraform.tfvars to config bucket:
       gsutil cp terraform.tfvars gs://${google_storage_bucket.config.name}/

    4. Create secrets in Secret Manager:
       ./scripts/create-secrets.sh

    5. Deploy infrastructure:
       terraform plan
       terraform apply
  EOT
}
