# ponytail: one shared redis:7-alpine (no auth, no persistence) for gitlab
# (logical DB 0) and authentik (logical DB 1). argocd keeps its bundled redis.
resource "kubernetes_namespace" "redis" {
  metadata {
    name = "redis"
  }
}

resource "helm_release" "redis" {
  name              = "redis"
  chart             = "${path.module}/../../helm/redis"
  namespace         = kubernetes_namespace.redis.metadata[0].name
  timeout           = 300
  dependency_update = true

  depends_on = [kubernetes_namespace.redis]
}
