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
          redirect_uri: "${local.app_url["gitlab"]}/users/auth/openid_connect/callback"
          authorization_endpoint: "${local.authentik_url}/application/o/authorize/"
          token_endpoint: "http://authentik-server.authentik.svc.cluster.local/application/o/token/"
          userinfo_endpoint: "http://authentik-server.authentik.svc.cluster.local/application/o/userinfo/"
          jwks_uri: "http://authentik-server.authentik.svc.cluster.local/application/o/gitlab/jwks/"
    EOT
  }

  depends_on = [kubernetes_namespace.gitlab]
}

# ponytail: consolidated object storage -> MinIO S3 (fog connection blob).
# Mirrors helm/gitlab/Tiltfile. Without this the chart renders object_store
# with no `connection`, so Gitlab.config.artifacts.object_store.enabled is
# false — every settings-page save then fails validation ("Incremental logging
# cannot be turned on without configuring object storage for artifacts") and
# artifacts/LFS/uploads/packages/etc silently fall back to local disk.
resource "kubernetes_secret" "gitlab_object_storage" {
  metadata {
    name      = "gitlab-object-storage"
    namespace = kubernetes_namespace.gitlab.metadata[0].name
  }

  data = {
    connection = yamlencode({
      provider              = "AWS"
      region                = "us-east-1"
      endpoint              = "http://minio.minio.svc.cluster.local:9000"
      path_style            = true
      aws_access_key_id     = "admin"
      aws_secret_access_key = var.minio_root_password
    })
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
  # ponytail: the bundled gitlab-runner can't go Ready until
  # null_resource.gitlab_runner_auth_token (below) mints it a glrt- token —
  # which depends on this release. Waiting here deadlocks; don't.
  wait = false

  values = [file("${path.module}/../helm/gitlab/values.yaml")]

  set {
    name  = "gitlab.global.initialRootPassword.secret"
    value = kubernetes_secret.gitlab_root_password.metadata[0].name
  }

  # GitLab bakes its external URL into generated links (incl. the Web IDE OAuth
  # callback). The Tailscale operator gives it a dedicated MagicDNS host on 443,
  # so the non-standard-port problem that forced bare-443 before is gone.
  set {
    name  = "gitlab.global.hosts.https"
    value = "true"
  }
  set {
    name  = "gitlab.global.hosts.gitlab.name"
    value = "gitlab.${local.tailnet_domain}"
  }
  set {
    name  = "gitlab.global.hosts.gitlab.https"
    value = "true"
  }

  # ponytail: this wrapper chart's own plain postgres:16 StatefulSet (not bitnami);
  # the template also renders gitlab-postgres-secret that global.psql points at.
  set_sensitive {
    name  = "postgres.password"
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
    name  = "gitlab.global.appConfig.object_store.connection.secret"
    value = kubernetes_secret.gitlab_object_storage.metadata[0].name
  }

  set {
    name  = "gitlab.global.appConfig.object_store.connection.key"
    value = "connection"
  }

  set {
    name  = "gitlab.certmanager-issuer.email"
    value = var.admin_email
  }

  depends_on = [kubernetes_namespace.gitlab, kubernetes_secret.gitlab_omniauth_authentik, kubernetes_secret.gitlab_object_storage, kubernetes_secret.gitlab_runner_cache_credentials, kubectl_manifest.homelab_ca_issuer]
}

# ponytail: mirrors Tiltfile's gitlab-promote-admin — promotes ADMIN_EMAIL to
# admin (no-op until they've logged in via SSO once) and realigns the
# internally-managed "GitLab Web IDE" OAuth app redirect_uri with the current
# host (stale after a device/host change -> 'callback URL do not match').
# Safe to re-run any time.
resource "null_resource" "gitlab_promote_admin" {
  triggers = {
    admin_email = var.admin_email
    gitlab_host = "gitlab.${local.tailnet_domain}"
    script_hash = filesha1("${path.module}/../helm/gitlab/promote-admin.sh")
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = "'${local.bash_bin}' '${local_file.gitlab_promote_admin_script.filename}'"
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

# ponytail: mirrors Tiltfile's gitlab-runner-auth-token — GitLab 18 dropped
# runner registration tokens, so mint a glrt- auth token from the webservice
# pod, write it into gitlab-gitlab-runner-secret, restart the runner. Without
# this the bundled runner 403s on every registration attempt and crashloops.
# Re-runs whenever the gitlab release revision changes (fresh deploy / rebuild).
resource "null_resource" "gitlab_runner_auth_token" {
  triggers = {
    release_revision = helm_release.gitlab.metadata[0].revision
    script_hash      = filesha1("${path.module}/../helm/gitlab/setup-runner-token.sh")
    inner_hash       = filesha1("${path.module}/../helm/gitlab/runner-auth-token.sh")
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = "'${local.bash_bin}' '${local_file.gitlab_runner_auth_token_script.filename}'"
  }

  depends_on = [helm_release.gitlab, local_file.gitlab_runner_auth_token_script]
}

resource "local_file" "gitlab_runner_auth_token_script" {
  filename = "${path.module}/.gitlab-runner-auth-token.sh"
  content = join("\n", [
    "cd '${abspath(path.module)}/../helm/gitlab'",
    "'${local.bash_bin}' setup-runner-token.sh",
    "",
  ])
}
