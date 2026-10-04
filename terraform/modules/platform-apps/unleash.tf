resource "kubernetes_namespace" "unleash" {
  count = var.enable_unleash ? 1 : 0
  metadata {
    name = "unleash"
  }
}

resource "helm_release" "unleash" {
  count             = var.enable_unleash ? 1 : 0
  name              = "unleash"
  chart             = "${path.module}/../../../helm/unleash"
  namespace         = kubernetes_namespace.unleash[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/unleash/values.yaml")]

  set {
    name  = "unleash.env[0].name"
    value = "INIT_ADMIN_API_TOKENS"
  }
  set_sensitive {
    name  = "unleash.env[0].value"
    value = "*:*.${var.phase_unleash_admin_password}"
  }
}
