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

# ponytail: MagicDNS suffix of the tailnet (everything after the first label of
# ts_host). Each app's tailscale Ingress is reachable at <app>.<tailnet_domain>.
variable "tailnet_domain" {
  type    = string
  default = ""
}

variable "bash_bin" {
  type    = string
  default = ""
  # Override only if Git Bash isn't at the default Windows path. Empty =
  # auto-detect (see locals.tf bash_bin).
}

variable "tailscale_oauth_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tailscale_oauth_client_secret" {
  type      = string
  sensitive = true
  default   = ""
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

variable "n8n_api_key" {
  type      = string
  sensitive = true
  default   = "" # create in n8n Settings -> API Keys; enables flow seeding
}

variable "n8n_owner_password" {
  type      = string
  sensitive = true
  default   = "Homelab-n8n-Dev-2026" # n8n requires an uppercase letter + digit
  # owner account the ansible n8n.yml playbook creates; email is admin_email
}

variable "n8n_db_password" {
  type      = string
  sensitive = true
  default   = "dev-n8n-db-password-not-for-prod-use"
}

variable "omp_gitlab_token" {
  type      = string
  sensitive = true
  default   = "" # GitLab token pushed into every omp pod by ansible omp.yml
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

variable "nextcloud_db_password" {
  type      = string
  sensitive = true
  default   = "dev-nextcloud-db-password"
}

variable "nextcloud_db_root_password" {
  type      = string
  sensitive = true
  default   = "dev-nextcloud-db-root-password"
}

variable "nextcloud_admin_password" {
  type      = string
  sensitive = true
  default   = "dev-nextcloud-admin-password"
}

variable "nextcloud_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-nextcloud-oidc-client-id"
}

variable "nextcloud_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-nextcloud-oidc-client-secret-not-for-prod-use"
}


variable "argocd_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-argocd-oidc-client-id"
}

variable "argocd_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-argocd-oidc-client-secret-not-for-prod-use"
}

variable "argocd_server_secret_key" {
  type      = string
  sensitive = true
  default   = "dev-argocd-server-secret-key-not-for-prod-use"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
  default   = "dev-grafana-admin-password"
}

variable "grafana_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-grafana-oidc-client-id"
}

variable "grafana_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-grafana-oidc-client-secret-not-for-prod-use"
}

variable "openwebui_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-openwebui-oidc-client-id"
}

variable "openwebui_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-openwebui-oidc-client-secret-not-for-prod-use"
}

variable "litellm_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-litellm-oidc-client-id"
}

variable "litellm_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-litellm-oidc-client-secret-not-for-prod-use"
}

variable "litellm_master_key" {
  type      = string
  sensitive = true
  default   = "sk-dev-litellm-master-key-not-for-prod-use"
}

variable "litellm_salt_key" {
  type      = string
  sensitive = true
  default   = "sk-dev-litellm-salt-key-not-for-prod-use"
}

variable "litellm_db_password" {
  type      = string
  sensitive = true
  default   = "dev-litellm-db-password"
}

variable "grafana_mcp_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "sonarqube_mcp_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "gitlab_mcp_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "gitlab_mcp_auth_token" {
  type      = string
  sensitive = true
  default   = "dev-gitlab-mcp-auth-token"
}

# Long-lived Claude Code OAuth token (`claude setup-token`) for the `claude` CLI
# inside omp pods. Blank = pods still start, `claude` just has no auth.
variable "claude_code_token" {
  type      = string
  sensitive = true
  default   = ""
}
