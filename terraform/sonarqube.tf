resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = "sonarqube"
  }
}

# ponytail: unlike minio.tf/gitlab.tf (which point straight at the upstream
# chart since they're single-dependency wrappers), sonarqube's values.yaml
# nests both the sonarqube and postgresql subchart values under their own
# keys — only correct when installed via the local wrapper chart itself.
resource "helm_release" "sonarqube" {
  name      = "sonarqube"
  chart     = "${path.module}/../helm/sonarqube"
  namespace = kubernetes_namespace.sonarqube.metadata[0].name
  timeout   = 600

  values = [replace(file("${path.module}/../helm/sonarqube/values.yaml"), "__TS_HOST__", var.ts_host)]

  set_sensitive {
    name  = "postgresql.auth.password"
    value = var.sonarqube_db_password
  }

  set_sensitive {
    name  = "sonarqube.jdbcOverwrite.jdbcPassword"
    value = var.sonarqube_db_password
  }

  depends_on = [kubernetes_namespace.sonarqube]
}
