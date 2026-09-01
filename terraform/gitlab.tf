resource "kubernetes_namespace" "gitlab" {
  metadata {
    name = "gitlab"
  }
}

resource "kubernetes_secret" "gitlab_root_password" {
  metadata {
    name      = "gitlab-initial-root-password"
    namespace = kubernetes_namespace.gitlab.metadata[0].name
  }

  data = {
    password = var.gitlab_root_password
  }
}

resource "kubernetes_secret" "gitlab_omniauth_authentik" {
  metadata {
    name      = "gitlab-omniauth-authentik"
    namespace = kubernetes_namespace.gitlab.metadata[0].name
  }

  data = {
    provider = <<-EOT
      name: openid_connect
      label: "Authentik"
      args:
        name: openid_connect
        scope: [openid, profile, email]
        response_type: code
        issuer: "http://authentik-server.authentik.svc.cluster.local/application/o/gitlab/"
        discovery: false
        uid_field: "preferred_username"
        client_options:
          identifier: "${var.gitlab_oidc_client_id}"
          secret: "${var.gitlab_oidc_client_secret}"
          redirect_uri: "https://${var.ts_host}/users/auth/openid_connect/callback"
          authorization_endpoint: "https://${var.ts_host}:8443/application/o/authorize/"
          token_endpoint: "http://authentik-server.authentik.svc.cluster.local/application/o/token/"
          userinfo_endpoint: "http://authentik-server.authentik.svc.cluster.local/application/o/userinfo/"
          jwks_uri: "http://authentik-server.authentik.svc.cluster.local/application/o/gitlab/jwks/"
    EOT
  }

  depends_on = [kubernetes_namespace.gitlab]
}

# ponytail: gitlab-runner distributed cache -> MinIO S3. Runner subchart's
# cache secret expects literal keys accesskey/secretkey.
resource "kubernetes_secret" "gitlab_runner_cache_credentials" {
  metadata {
    name      = "gitlab-runner-cache-credentials"
    namespace = kubernetes_namespace.gitlab.metadata[0].name
  }

  data = {
    accesskey = "admin"
    secretkey = var.minio_root_password
  }

  depends_on = [kubernetes_namespace.gitlab]
}

resource "helm_release" "gitlab" {
  name              = "gitlab"
  chart             = "${path.module}/../helm/gitlab"
  namespace         = kubernetes_namespace.gitlab.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [file("${path.module}/../helm/gitlab/values.yaml")]

  set {
    name  = "gitlab.global.initialRootPassword.secret"
    value = kubernetes_secret.gitlab_root_password.metadata[0].name
  }

  # GitLab bakes its external URL into generated links, including the
  # internally-managed "GitLab Web IDE" OAuth app callback
  # (https://<host>/-/ide/oauth_redirect). The chart has no non-standard-port
  # support here, so GitLab is served on the tailnet's 443
  # (scripts/tailscale-serve.sh) and only the host is set.
  set {
    name  = "gitlab.global.hosts.https"
    value = "true"
  }
  set {
    name  = "gitlab.global.hosts.gitlab.name"
    value = var.ts_host
  }
  set {
    name  = "gitlab.global.hosts.gitlab.https"
    value = "true"
  }

  set_sensitive {
    name  = "gitlab.postgresql.auth.password"
    value = var.gitlab_db_password
  }

  set {
    name  = "gitlab.global.appConfig.omniauth.enabled"
    value = "true"
  }

  set {
    name  = "gitlab.global.appConfig.omniauth.blockAutoCreatedUsers"
    value = "false"
  }

  set {
    name  = "gitlab.global.appConfig.omniauth.allowSingleSignOn[0]"
    value = "openid_connect"
  }

  set {
    name  = "gitlab.global.appConfig.omniauth.autoSignInWithProvider"
    value = "openid_connect"
  }

  set {
    name  = "gitlab.global.appConfig.omniauth.providers[0].secret"
    value = kubernetes_secret.gitlab_omniauth_authentik.metadata[0].name
  }

  set {
    name  = "gitlab.global.appConfig.omniauth.providers[0].key"
    value = "provider"
  }

  set {
    name  = "gitlab.certmanager-issuer.email"
    value = var.admin_email
  }

  depends_on = [kubernetes_namespace.gitlab, kubernetes_secret.gitlab_omniauth_authentik, kubernetes_secret.gitlab_runner_cache_credentials, kubectl_manifest.homelab_ca_issuer]
}

# ponytail: mirrors Tiltfile's gitlab-promote-admin — promotes ADMIN_EMAIL to
# admin (no-op until they've logged in via SSO once) and realigns the
# internally-managed "GitLab Web IDE" OAuth app redirect_uri with the current
# host (stale after a device/host change -> 'callback URL do not match').
# Safe to re-run any time.
resource "null_resource" "gitlab_promote_admin" {
  triggers = {
    admin_email = var.admin_email
    ts_host     = var.ts_host
    script_hash = filesha1("${path.module}/../helm/gitlab/promote-admin.sh")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "bash '${local_file.gitlab_promote_admin_script.filename}'"
  }

  depends_on = [helm_release.gitlab, local_file.gitlab_promote_admin_script]
}

resource "local_file" "gitlab_promote_admin_script" {
  filename = "${path.module}/.gitlab-promote-admin.sh"
  content = join("\n", [
    "kubectl exec -i -n gitlab deploy/gitlab-webservice-default -c webservice -- env ADMIN_EMAIL='${var.admin_email}' sh < '${abspath(path.module)}/../helm/gitlab/promote-admin.sh'",
    "",
  ])
}
