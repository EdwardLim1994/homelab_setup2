resource "kubernetes_namespace" "mattermost" {
  metadata {
    name = "mattermost"
  }
}

# ponytail: mirrors Tiltfile's ca_cert_b64 injection — Mattermost needs to
# trust homelab's self-signed CA to make server-side OAuth calls to Authentik
# over Tailscale HTTPS.
data "kubernetes_secret" "homelab_ca" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [null_resource.homelab_ca_ready]
}

resource "kubernetes_secret" "mattermost_homelab_ca" {
  metadata {
    name      = "homelab-ca"
    namespace = kubernetes_namespace.mattermost.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.mattermost, data.kubernetes_secret.homelab_ca]
}

resource "helm_release" "mattermost" {
  name              = "mattermost"
  chart             = "${path.module}/../helm/mattermost"
  namespace         = kubernetes_namespace.mattermost.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(replace(replace(replace(replace(replace(
      file("${path.module}/../helm/mattermost/values.yaml"),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["mattermost"]),
      "__MATTERMOST_OIDC_CLIENT_ID__", var.mattermost_oidc_client_id),
      "__MATTERMOST_OIDC_CLIENT_SECRET__", var.mattermost_oidc_client_secret),
      "__MM_DB_PASSWORD__", var.mattermost_db_password),
    "__MINIO_ROOT_PASSWORD__", var.minio_root_password)
  ]

  depends_on = [kubernetes_namespace.mattermost, kubernetes_secret.mattermost_homelab_ca]
}
