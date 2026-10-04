resource "kubernetes_namespace" "vault" {
  count = var.enable_vault ? 1 : 0
  metadata {
    name = "vault"
  }
}

resource "helm_release" "vault" {
  count             = var.enable_vault ? 1 : 0
  name              = "vault"
  chart             = "${path.module}/../../../helm/vault"
  namespace         = kubernetes_namespace.vault[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/vault/values.yaml")]

  set_sensitive {
    name  = "vault.server.dev.devRootToken"
    value = var.phase_vault_root_token
  }
}
