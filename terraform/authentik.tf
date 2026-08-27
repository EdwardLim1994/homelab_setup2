resource "kubernetes_namespace" "authentik" {
  metadata {
    name = "authentik"
  }
}

resource "helm_release" "authentik" {
  name              = "authentik"
  chart             = "${path.module}/../helm/authentik"
  namespace         = kubernetes_namespace.authentik.metadata[0].name
  dependency_update = true

  values = [file("${path.module}/../helm/authentik/values.yaml")]

  set_sensitive {
    name  = "authentik.authentik.secret_key"
    value = var.authentik_secret_key
  }

  set_sensitive {
    name  = "authentik.authentik.postgresql.password"
    value = var.authentik_db_password
  }

  set_sensitive {
    name  = "authentik.postgresql.auth.password"
    value = var.authentik_db_password
  }

  set {
    name  = "authentik.global.env[0].name"
    value = "AUTHENTIK_BOOTSTRAP_TOKEN"
  }
  set_sensitive {
    name  = "authentik.global.env[0].value"
    value = var.authentik_bootstrap_token
  }
  set {
    name  = "authentik.global.env[1].name"
    value = "AUTHENTIK_BOOTSTRAP_PASSWORD"
  }
  set_sensitive {
    name  = "authentik.global.env[1].value"
    value = var.authentik_bootstrap_password
  }
  set {
    name  = "authentik.global.env[2].name"
    value = "AUTHENTIK_BOOTSTRAP_EMAIL"
  }
  set {
    name  = "authentik.global.env[2].value"
    value = "akadmin@authentik.local"
  }
  set {
    name  = "authentik.global.env[3].name"
    value = "GITHUB_OAUTH_CLIENT_ID"
  }
  set_sensitive {
    name  = "authentik.global.env[3].value"
    value = var.github_oauth_client_id
  }
  set {
    name  = "authentik.global.env[4].name"
    value = "GITHUB_OAUTH_CLIENT_SECRET"
  }
  set_sensitive {
    name  = "authentik.global.env[4].value"
    value = var.github_oauth_client_secret
  }

  depends_on = [kubernetes_namespace.authentik, kubectl_manifest.homelab_ca_issuer]
}

# ponytail: mirrors Tiltfile's authentik-github-source — chart doesn't
# create the GitHub OAuth source, its login-page identification stage
# binding, or the auto-promote-admin-on-enrollment policy by itself.
resource "null_resource" "authentik_github_source" {
  triggers = {
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
    admin_email   = var.admin_email
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "kubectl exec -i -n authentik deploy/authentik-server -- env GITHUB_OAUTH_CLIENT_ID=${var.github_oauth_client_id} GITHUB_OAUTH_CLIENT_SECRET=${var.github_oauth_client_secret} ADMIN_EMAIL=${var.admin_email} ak shell < \"${abspath(path.module)}/../helm/authentik/provision-github-source.py\""
  }

  depends_on = [helm_release.authentik]
}

# ponytail: mirrors Tiltfile's authentik-app-providers — nothing else
# creates each app's OAuth2Provider/Application in Authentik, so every app's
# OIDC client_id/secret set via helm_release is otherwise talking to a
# provider that doesn't exist ("client not found" / login errors).
resource "null_resource" "authentik_app_providers" {
  triggers = {
    gitlab_id       = var.gitlab_oidc_client_id
    gitlab_secret   = var.gitlab_oidc_client_secret
    minio_id        = var.minio_oidc_client_id
    minio_secret    = var.minio_oidc_client_secret
    n8n_id          = var.n8n_oidc_client_id
    n8n_secret      = var.n8n_oidc_client_secret
    sonarqube_id     = var.sonarqube_oidc_client_id
    sonarqube_secret = var.sonarqube_oidc_client_secret
    seafile_id      = var.seafile_oidc_client_id
    seafile_secret  = var.seafile_oidc_client_secret
    argocd_id       = var.argocd_oidc_client_id
    argocd_secret   = var.argocd_oidc_client_secret
    grafana_id      = var.grafana_oidc_client_id
    grafana_secret  = var.grafana_oidc_client_secret
    openwebui_id     = var.openwebui_oidc_client_id
    openwebui_secret = var.openwebui_oidc_client_secret
    litellm_id      = var.litellm_oidc_client_id
    litellm_secret  = var.litellm_oidc_client_secret
    admin_email     = var.admin_email
    ts_host         = var.ts_host
    script_hash     = filesha1("${path.module}/../helm/authentik/provision-app-providers.py")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    # ponytail: run a real script file, not an inline command string —
    # a long inline command with embedded quotes/redirection got mangled by
    # Windows CreateProcess argv re-escaping in a way a short two-token
    # command ("bash" + script path) sidesteps entirely.
    command = "bash '${local_file.authentik_app_providers_script.filename}'"
  }

  depends_on = [helm_release.authentik, local_file.authentik_app_providers_script]
}

# ponytail: content built with join("\n", ...) instead of a <<-EOT heredoc —
# this .tf file has CRLF line endings, and a heredoc captures the source
# file's literal bytes (including the \r), corrupting the script the same
# way the inline command above did.
resource "local_file" "authentik_app_providers_script" {
  filename = "${path.module}/.authentik-app-providers.sh"
  content = join("\n", [
    "set -e",
    "kubectl exec -i -n authentik deploy/authentik-server -- env \\",
    "  GITLAB_OIDC_CLIENT_ID='${var.gitlab_oidc_client_id}' GITLAB_OIDC_CLIENT_SECRET='${var.gitlab_oidc_client_secret}' \\",
    "  MINIO_OIDC_CLIENT_ID='${var.minio_oidc_client_id}' MINIO_OIDC_CLIENT_SECRET='${var.minio_oidc_client_secret}' \\",
    "  N8N_OIDC_CLIENT_ID='${var.n8n_oidc_client_id}' N8N_OIDC_CLIENT_SECRET='${var.n8n_oidc_client_secret}' \\",
    "  SONARQUBE_OIDC_CLIENT_ID='${var.sonarqube_oidc_client_id}' SONARQUBE_OIDC_CLIENT_SECRET='${var.sonarqube_oidc_client_secret}' \\",
    "  SEAFILE_OIDC_CLIENT_ID='${var.seafile_oidc_client_id}' SEAFILE_OIDC_CLIENT_SECRET='${var.seafile_oidc_client_secret}' \\",
    "  ARGOCD_OIDC_CLIENT_ID='${var.argocd_oidc_client_id}' ARGOCD_OIDC_CLIENT_SECRET='${var.argocd_oidc_client_secret}' \\",
    "  GRAFANA_OIDC_CLIENT_ID='${var.grafana_oidc_client_id}' GRAFANA_OIDC_CLIENT_SECRET='${var.grafana_oidc_client_secret}' \\",
    "  OPENWEBUI_OIDC_CLIENT_ID='${var.openwebui_oidc_client_id}' OPENWEBUI_OIDC_CLIENT_SECRET='${var.openwebui_oidc_client_secret}' \\",
    "  LITELLM_OIDC_CLIENT_ID='${var.litellm_oidc_client_id}' LITELLM_OIDC_CLIENT_SECRET='${var.litellm_oidc_client_secret}' \\",
    "  ADMIN_EMAIL='${var.admin_email}' TS_HOST='${var.ts_host}' NX_CLOUD_APP_URL='https://${var.ts_host}:8454' \\",
    "  ak shell < '${abspath(path.module)}/../helm/authentik/provision-app-providers.py'",
    "",
  ])
}
