variable "authentik_secret_key" {
  type      = string
  sensitive = true
  default   = "dev-authentik-secret-key-not-for-prod-use"
}

# ponytail: one password for every app role on the shared postgres
# (helm/postgres). Replaces the old per-app *_db_password vars. nextcloud keeps
# its own (nextcloud_db_password) — different engine (MariaDB).
variable "shared_db_password" {
  type      = string
  sensitive = true
  default   = "dev-shared-db-password-not-for-prod-use"
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

variable "n8n_owner_password" {
  type      = string
  sensitive = true
  default   = "Homelab-n8n-Dev-2026" # n8n requires an uppercase letter + digit
  # owner account the ansible n8n.yml playbook creates; email is admin_email
}

variable "omp_gitlab_token" {
  type      = string
  sensitive = true
  default   = "" # GitLab token pushed into every omp pod by ansible omp.yml
}

variable "argocd_token" {
  type      = string
  sensitive = true
  # external-service token, minted by hand once ArgoCD is up:
  # argocd login <argocd-url> --username admin --password <initial-admin-secret>
  # argocd account generate-token --account n8n
  default = ""
}

variable "omp_gitlab_repo_url" {
  type    = string
  default = "" # clone URL microservice-rnd1 — omp-agent Job pods git-clone this
}

variable "gitlab_webhook_secret" {
  type      = string
  sensitive = true
  # X-GitLab-Token shared secret: F-00 (n8n) verifies it, the
  # gitlab-webhook.yml playbook registers the hook with it. Same value both ends.
  default   = "dev-gitlab-webhook-secret-not-for-prod-use"
}

variable "gitlab_group_id" {
  type    = string
  default = "" # numeric id or path; blank = gitlab-webhook.yml auto-discovers
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

variable "kafka_ui_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-kafka-ui-oidc-client-id"
}

variable "kafka_ui_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-kafka-ui-oidc-client-secret-not-for-prod-use"
}

variable "taiga_api_token" {
  # bootstrap-from-this-stack, like n8n_mcp_api_key/openwebui_api_key — leave
  # blank, mint by hand once Taiga is up (admin user's API token).
  type      = string
  sensitive = true
  default   = ""
}

variable "taiga_admin_password" {
  type      = string
  sensitive = true
  default   = "dev-taiga-admin-password-not-for-prod-use"
}

variable "taiga_secret_key" {
  # Django SECRET_KEY (TAIGA_SECRET_KEY) — cryptographic signing, not an
  # auth credential shared with anything else.
  type      = string
  sensitive = true
  default   = "dev-taiga-secret-key-not-for-prod-use"
}

variable "taiga_rabbitmq_password" {
  type      = string
  sensitive = true
  default   = "dev-taiga-rabbitmq-password-not-for-prod-use"
}

variable "taiga_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-taiga-oidc-client-id"
}

variable "taiga_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-taiga-oidc-client-secret-not-for-prod-use"
}

variable "harbor_admin_password" {
  type      = string
  sensitive = true
  default   = "dev-harbor-admin-password-not-for-prod-use"
}

variable "harbor_oidc_client_id" {
  type      = string
  sensitive = true
  default   = "dev-harbor-oidc-client-id"
}

variable "harbor_oidc_client_secret" {
  type      = string
  sensitive = true
  default   = "dev-harbor-oidc-client-secret-not-for-prod-use"
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

# ponytail: per-caller bearer for the taiga MCP server (its AUTH_TOKEN). Not
# a real credential — this repo invents it, same as gitlab_mcp_auth_token
# above. Distinct from taiga_api_token, which is the upstream Taiga
# credential the server itself holds (its TAIGA_TOKEN).
variable "taiga_mcp_auth_token" {
  type      = string
  sensitive = true
  default   = "dev-taiga-mcp-auth-token-not-for-prod-use"
}

# ponytail: per-caller bearer for the n8n MCP server (its AUTH_TOKEN). LiteLLM
# forwards it. Not a real credential — this repo invents it. n8n-mcp wants >= 32
# chars in http mode.
variable "n8n_mcp_auth_token" {
  type      = string
  sensitive = true
  default   = "dev-n8n-mcp-auth-token-not-for-prod-use-000"
}

# ponytail: n8n's own API key (mcp-servers-n8n's N8N_API_KEY) — distinct from
# n8n_mcp_auth_token above (that's the caller bearer *into* the MCP server;
# this is what the MCP server uses to call *into* n8n). Blank default:
# playbooks/n8n.yml mints one on first run and tells you to paste it here.
variable "n8n_mcp_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

# ponytail: OpenWebUI personal API key for playbooks/openwebui.yml (installs
# helm/ansible/pipe/sdlc_pipe.py as a Function via the admin API). SSO-only
# login means this can't be scripted like n8n's owner login — generate it
# once via Settings -> Account -> API Keys after logging in through the
# browser, then paste it here.
variable "openwebui_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

# Long-lived Claude Code OAuth token (`claude setup-token`) for the `claude` CLI
# inside omp pods. Blank = pods still start, `claude` just has no auth.
variable "claude_code_token" {
  type      = string
  sensitive = true
  default   = ""
}

# ponytail: NodePort on internal's k3d loadbalancer that sit/uat/production's
# opencost remote_writes to via host.docker.internal — same bridge pattern as
# REGISTRY_MIRROR_PORT (scripts/create-cluster.*), see observability.tf.
variable "mimir_push_port" {
  type    = number
  default = 30510
}

# ponytail: same bridge, for sit/uat/production's log-shipper (helm/log-shipper,
# terraform/modules/platform-apps/log-shipper.tf) to push logs into internal's
# Loki. See observability.tf's loki_nodeport Service.
variable "loki_push_port" {
  type    = number
  default = 30511
}

# ponytail: same bridge, for sit/uat/production's log-shipper to push traces
# (received via its own in-cluster OTLP endpoint, apps push to that) into
# internal's Tempo. See observability.tf's tempo_nodeport Service.
variable "tempo_push_port" {
  type    = number
  default = 30512
}
