# Secret Manager Integration Metadata
# Provides non-sensitive references to secrets provisioned for the Gitea stack.

locals {
  secret_manager_secret_names = {
    admin_password        = local.admin_password_secret
    postgres_password     = local.db_password_secret
    runner_token          = local.runner_token_secret
    gitea_secret_key      = local.gitea_secret_key_secret
    gitea_internal_token  = local.gitea_internal_token_secret
    gitea_oauth2_jwt      = local.gitea_oauth2_jwt_secret
    gitea_metrics_token   = local.gitea_metrics_token_secret
  }
}

output "secret_manager_secret_names" {
  description = "Fully-qualified Secret Manager resource names used by the deployment."
  value       = local.secret_manager_secret_names
}

output "secret_manager_enabled" {
  description = "Indicates whether Secret Manager integration is enabled for the deployment."
  value       = var.enable_secret_manager
}
