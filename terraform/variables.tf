variable "authentik_secret_key" {
  type      = string
  sensitive = true
  default   = "dev-authentik-secret-key-not-for-prod-use"
}

variable "authentik_db_password" {
  type      = string
  sensitive = true
  default   = "dev-authentik-db-password"
}

variable "authentik_bootstrap_token" {
  type      = string
  sensitive = true
  default   = "dev-authentik-bootstrap-token-not-for-prod-use"
}

variable "authentik_bootstrap_password" {
  type      = string
  sensitive = true
  default   = "Admin1234!"
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
  type    = string
  default = "edwardlimkoksiong1994@gmail.com"
}

variable "ts_host" {
  type = string
}

variable "gitlab_root_password" {
  type      = string
  sensitive = true
  default   = "dev-gitlab-root-password"
}

variable "gitlab_db_password" {
  type      = string
  sensitive = true
  default   = "dev-gitlab-db-password"
}

variable "gitlab_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-gitlab-oidc-client-id"
}

variable "gitlab_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-gitlab-oidc-client-secret-not-for-prod-use"
}

variable "minio_root_password" {
  type      = string
  sensitive = true
  default   = "dev-minio-root-password"
}

variable "minio_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-minio-oidc-client-id"
}

variable "minio_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-minio-oidc-client-secret-not-for-prod-use"
}

variable "n8n_encryption_key" {
  type      = string
  sensitive = true
  default   = "dev-n8n-encryption-key-not-for-prod-use"
}

variable "n8n_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-n8n-oidc-client-id"
}

variable "n8n_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-n8n-oidc-client-secret-not-for-prod-use"
}

variable "sonarqube_db_password" {
  type      = string
  sensitive = true
  default   = "dev-sonarqube-db-password"
}

variable "sonarqube_monitoring_passcode" {
  type      = string
  sensitive = true
  default   = "dev-sonarqube-monitoring-passcode"
}

variable "sonarqube_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-sonarqube-oidc-client-id"
}

variable "sonarqube_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-sonarqube-oidc-client-secret-not-for-prod-use"
}

variable "seafile_db_password" {
  type      = string
  sensitive = true
  default   = "dev-seafile-db-password"
}

variable "seafile_db_root_password" {
  type      = string
  sensitive = true
  default   = "dev-seafile-db-root-password"
}

variable "seafile_admin_password" {
  type      = string
  sensitive = true
  default   = "dev-seafile-admin-password"
}

variable "seafile_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-seafile-oidc-client-id"
}

variable "seafile_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-seafile-oidc-client-secret-not-for-prod-use"
}

variable "seafile_jwt_private_key" {
  type      = string
  sensitive = true
  default   = "dev-seafile-jwt-private-key-not-for-prod-use"
}
