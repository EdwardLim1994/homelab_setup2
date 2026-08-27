resource "kubernetes_namespace" "nx_cloud" {
  metadata {
    name = "nx-cloud"
  }
}

# ponytail: mirrors Tiltfile's nx-cloud-secrets — same keys, same
# mongodb/valkey service names (bitnami subchart defaults for release "nx-cloud").
resource "kubernetes_secret" "nx_cloud_secrets" {
  metadata {
    name      = "nx-cloud-secrets"
    namespace = kubernetes_namespace.nx_cloud.metadata[0].name
  }
  data = {
    NX_CLOUD_MONGO_SERVER_ENDPOINT = "mongodb://nx-cloud:${var.nx_cloud_mongo_password}@nx-cloud-mongodb-0.nx-cloud-mongodb-headless:27017/nx-cloud?replicaSet=rs0"
    VALKEY_PASSWORD                = var.nx_cloud_valkey_password
    ADMIN_PASSWORD                 = var.nx_cloud_admin_password
    # ponytail: frontend throws SAML_NO_CERT_ERROR at boot if entry point is
    # set but cert isn't — keep both empty together until saml_cert is real.
    SAML_ENTRY_POINT = var.nx_cloud_saml_cert == "" ? "" : "https://${var.ts_host}:8443/application/saml/nx-cloud/sso/binding/redirect/"
    SAML_CERT         = var.nx_cloud_saml_cert
  }
  depends_on = [kubernetes_namespace.nx_cloud]
}

resource "helm_release" "nx_cloud" {
  name              = "nx-cloud"
  chart             = "${path.module}/../helm/nx-cloud"
  namespace         = kubernetes_namespace.nx_cloud.metadata[0].name
  timeout           = 600
  dependency_update = true
  # ponytail: app-level readiness (frontend SAML boot check etc.) isn't
  # terraform's job to babysit — don't block 10min on it, k8s reconciles on its own.
  wait = false

  values = [file("${path.module}/../helm/nx-cloud/values.yaml")]

  set {
    name  = "nx-cloud.global.nxCloudAppURL"
    value = "https://${var.ts_host}:8454"
  }

  set_sensitive {
    name  = "mongodb.auth.rootPassword"
    value = var.nx_cloud_mongo_password
  }

  set_sensitive {
    name  = "mongodb.auth.passwords[0]"
    value = var.nx_cloud_mongo_password
  }

  set_sensitive {
    name  = "valkey.auth.password"
    value = var.nx_cloud_valkey_password
  }

  # ponytail: reuses minio root creds like the Tiltfile does; give nx-cloud
  # its own scoped minio service account if this ever leaves dev.
  set_sensitive {
    name  = "nx-cloud.api.deployment.env.AWS_S3_ACCESS_KEY_ID"
    value = "admin"
  }

  set_sensitive {
    name  = "nx-cloud.api.deployment.env.AWS_S3_SECRET_ACCESS_KEY"
    value = var.minio_root_password
  }

  depends_on = [kubernetes_namespace.nx_cloud, kubernetes_secret.nx_cloud_secrets]
}
