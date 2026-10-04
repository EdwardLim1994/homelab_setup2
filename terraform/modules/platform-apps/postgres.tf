# ponytail: reuses helm/postgres (plain postgres:16, official image) instead
# of authentik's bundled bitnami postgresql subchart. Single-app db list here
# — unlike internal's shared instance, only authentik needs Postgres in a
# phase cluster right now (unleash brings its own via its chart).
resource "kubernetes_namespace" "postgres" {
  count = var.enable_authentik ? 1 : 0
  metadata {
    name = "postgres"
  }
}

resource "helm_release" "postgres" {
  count             = var.enable_authentik ? 1 : 0
  name              = "postgres"
  chart             = "${path.module}/../../../helm/postgres"
  namespace         = kubernetes_namespace.postgres[0].metadata[0].name
  dependency_update = true
  timeout           = 300

  set {
    name  = "databases[0]"
    value = "authentik"
  }
  set {
    name  = "gitlabDatabase"
    value = ""
  }

  set_sensitive {
    name  = "password"
    value = var.phase_shared_db_password
  }
}
