resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
  }
}

resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.4.0"
  namespace  = kubernetes_namespace.minio.metadata[0].name

  values = [replace(file("${path.module}/../helm/minio/values.yaml"), "__TS_HOST__", var.ts_host)]

  set_sensitive {
    name  = "minio.rootPassword"
    value = var.minio_root_password
  }

  depends_on = [kubernetes_namespace.minio]
}
