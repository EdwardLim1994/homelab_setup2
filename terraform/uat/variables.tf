variable "phase_authentik_secret_key" {
  type      = string
  sensitive = true
  default   = "dev-phase-authentik-secret-key-not-for-prod-use"
}

variable "phase_authentik_bootstrap_password" {
  type      = string
  sensitive = true
  default   = "Admin1234!"
}

variable "phase_authentik_bootstrap_token" {
  type      = string
  sensitive = true
  default   = "dev-phase-authentik-bootstrap-token-not-for-prod-use"
}

variable "phase_shared_db_password" {
  type      = string
  sensitive = true
  default   = "dev-phase-shared-db-password-not-for-prod-use"
}

variable "phase_unleash_admin_password" {
  type      = string
  sensitive = true
  default   = "dev-phase-unleash-admin-password-not-for-prod-use"
}

variable "phase_vault_root_token" {
  type      = string
  sensitive = true
  default   = "dev-phase-vault-root-token-not-for-prod-use"
}

variable "phase_meilisearch_master_key" {
  type      = string
  sensitive = true
  default   = "dev-phase-meilisearch-master-key-not-for-prod-use"
}

variable "phase_minio_root_password" {
  type      = string
  sensitive = true
  default   = "dev-phase-minio-root-password-not-for-prod-use"
}
