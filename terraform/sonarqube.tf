resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = "sonarqube"
  }
}

resource "kubernetes_secret" "sonarqube_oidc" {
  metadata {
    name      = "sonarqube-oidc-secret"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }
  data = {
    "secret.properties" = join("\n", [
      "sonar.auth.oidc.clientId.secured=${var.sonarqube_oidc_client_id}",
      "sonar.auth.oidc.clientSecret.secured=${var.sonarqube_oidc_client_secret}",
      "sonar.core.serverBaseURL=https://${var.ts_host}:8448",
      "sonar.auth.oidc.issuerUri=https://${var.ts_host}:8443/application/o/sonarqube/",
    ])
  }
  depends_on = [kubernetes_namespace.sonarqube]
}

# ponytail: values.yaml nests sonarqube and postgresql subchart values under
# their own keys — only correct when installed via the local wrapper chart.
resource "helm_release" "sonarqube" {
  name              = "sonarqube"
  chart             = "${path.module}/../helm/sonarqube"
  namespace         = kubernetes_namespace.sonarqube.metadata[0].name
  timeout           = 900
  dependency_update = true

  values = [replace(file("${path.module}/../helm/sonarqube/values.yaml"), "__TS_HOST__", var.ts_host)]

  set_sensitive {
    name  = "postgresql.auth.password"
    value = var.sonarqube_db_password
  }

  set_sensitive {
    name  = "sonarqube.jdbcOverwrite.jdbcPassword"
    value = var.sonarqube_db_password
  }

  set_sensitive {
    name  = "sonarqube.monitoringPasscode"
    value = var.sonarqube_monitoring_passcode
  }

  depends_on = [kubernetes_namespace.sonarqube, kubernetes_secret.sonarqube_oidc]
}
