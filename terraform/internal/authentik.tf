resource "kubernetes_namespace" "authentik" {
  metadata {
    name = "authentik"
  }
}

resource "helm_release" "authentik" {
  name              = "authentik"
  chart             = "${path.module}/../../helm/authentik"
  namespace         = kubernetes_namespace.authentik.metadata[0].name
  dependency_update = true
  # ponytail: fresh-DB first boot runs migrations + blueprint import, blows past
  # the 300s helm default. Match the other DB-backed apps.
  timeout = 900

  values = [file("${path.module}/../../helm/authentik/values.yaml")]

  set_sensitive {
    name  = "authentik.authentik.secret_key"
    value = var.authentik_secret_key
  }

  # shared postgres (helm/postgres)
  set_sensitive {
    name  = "authentik.authentik.postgresql.password"
    value = var.shared_db_password
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

  depends_on = [kubernetes_namespace.authentik, kubectl_manifest.homelab_ca_issuer, helm_release.postgres, helm_release.redis]
}

# ponytail: chart doesn't create the GitHub OAuth source, its login-page
# identification stage binding, or the auto-promote-admin-on-enrollment
# policy by itself.
resource "null_resource" "authentik_github_source" {
  triggers = {
    client_id     = var.github_oauth_client_id
    client_secret = var.github_oauth_client_secret
    admin_email   = var.admin_email
    # ponytail: re-run on a fresh Authentik deploy — its DB is wiped on every
    # cluster rebuild and the source/provider objects go with it, but the vars
    # above don't change so nothing else would retrigger this.
    authentik_release = helm_release.authentik.metadata[0].revision
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = "kubectl --context ${var.kube_context} exec -i -n authentik deploy/authentik-server -- env GITHUB_OAUTH_CLIENT_ID=${var.github_oauth_client_id} GITHUB_OAUTH_CLIENT_SECRET=${var.github_oauth_client_secret} ADMIN_EMAIL=${var.admin_email} ak shell < \"${abspath(path.module)}/../../helm/authentik/provision-github-source.py\""
  }

  depends_on = [helm_release.authentik]
}

# ponytail: nothing else creates each app's OAuth2Provider/Application in
# Authentik, so every app's
# OIDC client_id/secret set via helm_release is otherwise talking to a
# provider that doesn't exist ("client not found" / login errors).
resource "null_resource" "authentik_app_providers" {
  triggers = {
    gitlab_id        = var.gitlab_oidc_client_id
    gitlab_secret    = var.gitlab_oidc_client_secret
    minio_id         = var.minio_oidc_client_id
    minio_secret     = var.minio_oidc_client_secret
    n8n_id           = var.n8n_oidc_client_id
    n8n_secret       = var.n8n_oidc_client_secret
    sonarqube_id     = var.sonarqube_oidc_client_id
    sonarqube_secret = var.sonarqube_oidc_client_secret
    nextcloud_id     = var.nextcloud_oidc_client_id
    nextcloud_secret = var.nextcloud_oidc_client_secret
    argocd_id        = var.argocd_oidc_client_id
    argocd_secret    = var.argocd_oidc_client_secret
    grafana_id       = var.grafana_oidc_client_id
    grafana_secret   = var.grafana_oidc_client_secret
    litellm_id       = var.litellm_oidc_client_id
    litellm_secret   = var.litellm_oidc_client_secret
    openwebui_id     = var.openwebui_oidc_client_id
    openwebui_secret = var.openwebui_oidc_client_secret
    kafka_ui_id      = var.kafka_ui_oidc_client_id
    kafka_ui_secret  = var.kafka_ui_oidc_client_secret
    harbor_id        = var.harbor_oidc_client_id
    harbor_secret    = var.harbor_oidc_client_secret
    taiga_id         = var.taiga_oidc_client_id
    taiga_secret     = var.taiga_oidc_client_secret
    admin_email      = var.admin_email
    app_domain       = local.tailnet_domain
    script_hash      = filesha1("${path.module}/../../helm/authentik/provision-app-providers.py")
    # ponytail: re-run on a fresh Authentik deploy (DB wiped on cluster rebuild).
    authentik_release = helm_release.authentik.metadata[0].revision
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    # ponytail: run a real script file, not an inline command string —
    # a long inline command with embedded quotes/redirection got mangled by
    # Windows CreateProcess argv re-escaping in a way a short two-token
    # command ("bash" + script path) sidesteps entirely.
    command = "'${local.bash_bin}' '${local_file.authentik_app_providers_script.filename}'"
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
    "kubectl --context ${var.kube_context} exec -i -n authentik deploy/authentik-server -- env \\",
    "  GITLAB_OIDC_CLIENT_ID='${var.gitlab_oidc_client_id}' GITLAB_OIDC_CLIENT_SECRET='${var.gitlab_oidc_client_secret}' \\",
    "  MINIO_OIDC_CLIENT_ID='${var.minio_oidc_client_id}' MINIO_OIDC_CLIENT_SECRET='${var.minio_oidc_client_secret}' \\",
    "  N8N_OIDC_CLIENT_ID='${var.n8n_oidc_client_id}' N8N_OIDC_CLIENT_SECRET='${var.n8n_oidc_client_secret}' \\",
    "  SONARQUBE_OIDC_CLIENT_ID='${var.sonarqube_oidc_client_id}' SONARQUBE_OIDC_CLIENT_SECRET='${var.sonarqube_oidc_client_secret}' \\",
    "  NEXTCLOUD_OIDC_CLIENT_ID='${var.nextcloud_oidc_client_id}' NEXTCLOUD_OIDC_CLIENT_SECRET='${var.nextcloud_oidc_client_secret}' \\",
    "  ARGOCD_OIDC_CLIENT_ID='${var.argocd_oidc_client_id}' ARGOCD_OIDC_CLIENT_SECRET='${var.argocd_oidc_client_secret}' \\",
    "  GRAFANA_OIDC_CLIENT_ID='${var.grafana_oidc_client_id}' GRAFANA_OIDC_CLIENT_SECRET='${var.grafana_oidc_client_secret}' \\",
    "  LITELLM_OIDC_CLIENT_ID='${var.litellm_oidc_client_id}' LITELLM_OIDC_CLIENT_SECRET='${var.litellm_oidc_client_secret}' \\",
    "  OPENWEBUI_OIDC_CLIENT_ID='${var.openwebui_oidc_client_id}' OPENWEBUI_OIDC_CLIENT_SECRET='${var.openwebui_oidc_client_secret}' \\",
    "  KAFKA_UI_OIDC_CLIENT_ID='${var.kafka_ui_oidc_client_id}' KAFKA_UI_OIDC_CLIENT_SECRET='${var.kafka_ui_oidc_client_secret}' \\",
    "  HARBOR_OIDC_CLIENT_ID='${var.harbor_oidc_client_id}' HARBOR_OIDC_CLIENT_SECRET='${var.harbor_oidc_client_secret}' \\",
    "  TAIGA_OIDC_CLIENT_ID='${var.taiga_oidc_client_id}' TAIGA_OIDC_CLIENT_SECRET='${var.taiga_oidc_client_secret}' \\",
    "  ADMIN_EMAIL='${var.admin_email}' APP_DOMAIN='${local.tailnet_domain}' \\",
    "  ak shell < '${abspath(path.module)}/../../helm/authentik/provision-app-providers.py'",
    "",
  ])
}
