resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
  }
}

# ponytail: MinIO trusts the homelab CA so its server-side OIDC discovery to
# authentik.<tailnet> (rewritten to traefik in terraform/coredns.tf) validates.
# Same read-and-copy pattern as mattermost.tf.
resource "kubernetes_secret" "minio_homelab_ca" {
  metadata {
    name      = "minio-homelab-ca"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.minio, data.kubernetes_secret.homelab_ca]
}

resource "helm_release" "minio" {
  name              = "minio"
  chart             = "${path.module}/../helm/minio"
  namespace         = kubernetes_namespace.minio.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(replace(replace(replace(replace(
      file("${path.module}/../helm/minio/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["minio"]),
      "__CONSOLE_URL__", local.app_url["minio-console"]),
    "__MINIO_TRUSTED_CA_SECRET__", kubernetes_secret.minio_homelab_ca.metadata[0].name),
  ]

  set_sensitive {
    name  = "minio.rootPassword"
    value = var.minio_root_password
  }

  set_sensitive {
    name  = "minio.environment.MINIO_IDENTITY_OPENID_CLIENT_ID"
    value = var.minio_oidc_client_id
  }

  set_sensitive {
    name  = "minio.environment.MINIO_IDENTITY_OPENID_CLIENT_SECRET"
    value = var.minio_oidc_client_secret
  }

  depends_on = [kubernetes_namespace.minio, kubernetes_secret.minio_homelab_ca]
}
