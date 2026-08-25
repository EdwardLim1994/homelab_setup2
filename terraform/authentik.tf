resource "kubernetes_namespace" "authentik" {
  metadata {
    name = "authentik"
  }
}

resource "helm_release" "authentik" {
  name              = "authentik"
  chart             = "${path.module}/../helm/authentik"
  namespace         = kubernetes_namespace.authentik.metadata[0].name
  dependency_update = true

  values = [file("${path.module}/../helm/authentik/values.yaml")]

  set_sensitive {
    name  = "authentik.authentik.secret_key"
    value = var.authentik_secret_key
  }

  set_sensitive {
    name  = "authentik.authentik.postgresql.password"
    value = var.authentik_db_password
  }

  set_sensitive {
    name  = "authentik.postgresql.auth.password"
    value = var.authentik_db_password
  }

  depends_on = [kubernetes_namespace.authentik, kubectl_manifest.homelab_ca_issuer]
}
