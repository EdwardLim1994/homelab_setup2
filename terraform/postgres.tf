# ponytail: one shared postgres:16 for authentik / gitlab / litellm / mattermost
# / n8n / sonarqube. Each app connects cross-namespace to
# postgres.postgres.svc.cluster.local:5432 with its own role + database
# (created by the chart's initdb script). nextcloud keeps its own MariaDB.
resource "kubernetes_namespace" "postgres" {
  metadata {
    name = "postgres"
  }
}

resource "helm_release" "postgres" {
  name              = "postgres"
  chart             = "${path.module}/../helm/postgres"
  namespace         = kubernetes_namespace.postgres.metadata[0].name
  timeout           = 600
  dependency_update = true

  set_sensitive {
    name  = "password"
    value = var.shared_db_password
  }

  depends_on = [kubernetes_namespace.postgres]
}
