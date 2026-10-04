resource "kubernetes_namespace" "litellm" {
  metadata {
    name = "litellm"
  }
}

# ponytail: __PLACEHOLDER__ -> secret substitution, one replace() per key.
locals {
  litellm_values = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
    file("${path.module}/../../helm/litellm/values.yaml"),
    "__TS_HOST__", var.ts_host),
    "__AUTHENTIK_URL__", local.authentik_url),
    "__APP_URL__", local.app_url["litellm"]),
    "__SHARED_DB_PASSWORD__", var.shared_db_password),
    "__N8N_MCP_AUTH_TOKEN__", var.n8n_mcp_auth_token),
    "__LITELLM_MASTER_KEY__", var.litellm_master_key),
    "__LITELLM_SALT_KEY__", var.litellm_salt_key),
    "__LITELLM_OIDC_CLIENT_ID__", var.litellm_oidc_client_id),
    "__LITELLM_OIDC_CLIENT_SECRET__", var.litellm_oidc_client_secret),
    "__GITLAB_MCP_AUTH_TOKEN__", var.gitlab_mcp_auth_token),
    "__SONARQUBE_MCP_TOKEN__", var.sonarqube_mcp_token),
  "__TAIGA_MCP_AUTH_TOKEN__", var.taiga_mcp_auth_token)
}

resource "helm_release" "litellm" {
  name              = "litellm"
  chart             = "${path.module}/../../helm/litellm"
  namespace         = kubernetes_namespace.litellm.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [local.litellm_values]

  depends_on = [kubernetes_namespace.litellm, helm_release.postgres]
}
