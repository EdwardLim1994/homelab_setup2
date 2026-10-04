# ponytail: no OIDC wiring (unlike helm/minio on internal) - helm/minio/
# values-phase.yaml is a standalone-mode, no-ingress, no-CA variant.

resource "kubernetes_namespace" "minio" {
  count = var.enable_minio ? 1 : 0
  metadata {
    name = "minio"
  }
}

resource "helm_release" "minio" {
  count             = var.enable_minio ? 1 : 0
  name              = "minio"
  chart             = "${path.module}/../../../helm/minio"
  namespace         = kubernetes_namespace.minio[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/minio/values-phase.yaml")]

  set {
    name  = "minio.rootUser"
    value = "admin"
  }

  set_sensitive {
    name  = "minio.rootPassword"
    value = var.phase_minio_root_password
  }
}
