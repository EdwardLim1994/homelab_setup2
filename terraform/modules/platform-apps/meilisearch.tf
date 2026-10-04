resource "kubernetes_namespace" "meilisearch" {
  count = var.enable_meilisearch ? 1 : 0
  metadata {
    name = "meilisearch"
  }
}

resource "helm_release" "meilisearch" {
  count             = var.enable_meilisearch ? 1 : 0
  name              = "meilisearch"
  chart             = "${path.module}/../../../helm/meilisearch"
  namespace         = kubernetes_namespace.meilisearch[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/meilisearch/values.yaml")]

  set_sensitive {
    name  = "meilisearch.environment.MEILI_MASTER_KEY"
    value = var.phase_meilisearch_master_key
  }
}
