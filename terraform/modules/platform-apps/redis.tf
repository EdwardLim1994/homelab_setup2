# ponytail: reuses helm/redis (plain redis:7-alpine, official image) instead
# of authentik's bundled bitnami redis subchart. Only authentik needs it here.
resource "kubernetes_namespace" "redis" {
  count = var.enable_authentik ? 1 : 0
  metadata {
    name = "redis"
  }
}

resource "helm_release" "redis" {
  count             = var.enable_authentik ? 1 : 0
  name              = "redis"
  chart             = "${path.module}/../../../helm/redis"
  namespace         = kubernetes_namespace.redis[0].metadata[0].name
  dependency_update = true
  timeout           = 300
}
