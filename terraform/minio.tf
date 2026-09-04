resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
  }
}

resource "helm_release" "minio" {
  name              = "minio"
  chart             = "${path.module}/../helm/minio"
  namespace         = kubernetes_namespace.minio.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(replace(replace(replace(
      file("${path.module}/../helm/minio/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["minio"]),
    "__CONSOLE_URL__", local.app_url["minio-console"]),
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

  depends_on = [kubernetes_namespace.minio]
}
