# Bootstrap Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "kms_location" {
  description = "Location for KMS keyring (global or regional)"
  type        = string
  default     = "us-central1"
}

variable "bucket_location" {
  description = "Location for GCS buckets (US, EU, ASIA, or specific region)"
  type        = string
  default     = "US"
}

variable "terraform_sa_email" {
  description = "Email of service account that will access Terraform state"
  type        = string
  default     = ""  # Will be created in main terraform
}
