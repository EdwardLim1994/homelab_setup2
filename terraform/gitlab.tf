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
          redirect_uri: "https://${var.ts_host}:8444/users/auth/openid_connect/callback"
          authorization_endpoint: "https://${var.ts_host}:8443/application/o/authorize/"
          token_endpoint: "http://authentik-server.authentik.svc.cluster.local/application/o/token/"
          userinfo_endpoint: "http://authentik-server.authentik.svc.cluster.local/application/o/userinfo/"
          jwks_uri: "http://authentik-server.authentik.svc.cluster.local/application/o/gitlab/jwks/"
    EOT
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

  depends_on = [kubernetes_namespace.gitlab, kubernetes_secret.gitlab_omniauth_authentik, kubectl_manifest.homelab_ca_issuer]
}
