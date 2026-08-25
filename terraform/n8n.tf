resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
  }
}

resource "helm_release" "n8n" {
  name       = "n8n"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "n8n"
  version    = "1.24.32"
  namespace  = kubernetes_namespace.n8n.metadata[0].name

  values = [replace(file("${path.module}/../helm/n8n/values.yaml"), "__TS_HOST__", var.ts_host)]

  depends_on = [kubernetes_namespace.n8n]
}
