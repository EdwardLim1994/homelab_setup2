resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = "sonarqube"
  }
}

# ponytail: SonarQube's OIDC plugin does discovery + token exchange
# server-side against authentik.<tailnet> — same homelab-CA trust gap as
# minio (see coredns.tf), but here it's a JVM truststore, not a generic
# trustedCertsSecret mount.
data "kubernetes_secret" "homelab_ca_sonarqube" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [null_resource.homelab_ca_ready]
}

resource "kubernetes_secret" "sonarqube_homelab_ca" {
  metadata {
    name      = "sonarqube-homelab-ca"
    namespace = kubernetes_namespace.sonarqube.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca_sonarqube.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.sonarqube, data.kubernetes_secret.homelab_ca_sonarqube]
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
      "sonar.core.serverBaseURL=${local.app_url["sonarqube"]}",
      "sonar.auth.oidc.issuerUri=${local.authentik_url}/application/o/sonarqube/",
    ])
  }
  depends_on = [kubernetes_namespace.sonarqube]
}

# ponytail: values.yaml nests sonarqube and postgresql subchart values under
# their own keys — only correct when installed via the local wrapper chart.
resource "helm_release" "sonarqube" {
  name              = "sonarqube"
  chart             = "${path.module}/../../helm/sonarqube"
  namespace         = kubernetes_namespace.sonarqube.metadata[0].name
  timeout           = 900
  dependency_update = true

  values = [
    replace(replace(replace(replace(
      file("${path.module}/../../helm/sonarqube/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["sonarqube"]),
    "__SONARQUBE_TRUSTED_CA_SECRET__", kubernetes_secret.sonarqube_homelab_ca.metadata[0].name),
  ]

  # shared postgres (helm/postgres)
  set_sensitive {
    name  = "sonarqube.jdbcOverwrite.jdbcPassword"
    value = var.shared_db_password
  }

  set_sensitive {
    name  = "sonarqube.monitoringPasscode"
    value = var.sonarqube_monitoring_passcode
  }

  depends_on = [kubernetes_namespace.sonarqube, kubernetes_secret.sonarqube_oidc, kubernetes_secret.sonarqube_homelab_ca, helm_release.postgres]
}
