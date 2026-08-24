variable "authentik_secret_key" {
  type      = string
  sensitive = true
}

variable "authentik_db_password" {
  type      = string
  sensitive = true
}

variable "authentik_bootstrap_token" {
  type      = string
  sensitive = true
}

variable "authentik_bootstrap_password" {
  type      = string
  sensitive = true
}

variable "github_oauth_client_id" {
  type      = string
  sensitive = true
}

variable "github_oauth_client_secret" {
  type      = string
  sensitive = true
}

variable "admin_email" {
  type = string
}

variable "gitlab_root_password" {
  type      = string
  sensitive = true
}

variable "gitlab_db_password" {
  type      = string
  sensitive = true
}

variable "gitlab_oidc_client_id" {
  type      = string
  sensitive = true
}

variable "gitlab_oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "minio_root_password" {
  type      = string
  sensitive = true
}

variable "minio_oidc_client_id" {
  type      = string
  sensitive = true
}

variable "minio_oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "n8n_encryption_key" {
  type      = string
  sensitive = true
}

variable "n8n_oidc_client_id" {
  type      = string
  sensitive = true
}

variable "n8n_oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "sonarqube_db_password" {
  type      = string
  sensitive = true
}

variable "sonarqube_monitoring_passcode" {
  type      = string
  sensitive = true
}

variable "sonarqube_oidc_client_id" {
  type      = string
  sensitive = true
}

variable "sonarqube_oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "seafile_db_password" {
  type      = string
  sensitive = true
}

variable "seafile_db_root_password" {
  type      = string
  sensitive = true
}

variable "seafile_admin_password" {
  type      = string
  sensitive = true
}

variable "seafile_oidc_client_id" {
  type      = string
  sensitive = true
}

variable "seafile_oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "seafile_jwt_private_key" {
  type      = string
  sensitive = true
}
