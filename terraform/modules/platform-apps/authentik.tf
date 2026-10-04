# ponytail: unlike helm/authentik on internal (points at one instance shared
# across 5 apps), this phase cluster gets its own dedicated postgres/redis
# pods (postgres.tf/redis.tf, official images) - not the goauthentik chart's
# bundled bitnami postgresql/redis subcharts.

resource "kubernetes_namespace" "authentik" {
  count = var.enable_authentik ? 1 : 0
  metadata {
    name = "authentik"
  }
}

resource "helm_release" "authentik" {
  count             = var.enable_authentik ? 1 : 0
  name              = "authentik"
  chart             = "${path.module}/../../../helm/authentik"
  namespace         = kubernetes_namespace.authentik[0].metadata[0].name
  dependency_update = true
  timeout           = 900

  values = [file("${path.module}/../../../helm/authentik/values-phase.yaml")]

  set_sensitive {
    name  = "authentik.authentik.secret_key"
    value = var.phase_authentik_secret_key
  }

  set_sensitive {
    name  = "authentik.authentik.postgresql.password"
    value = var.phase_shared_db_password
  }

  set {
    name  = "authentik.global.env[0].name"
    value = "AUTHENTIK_BOOTSTRAP_TOKEN"
  }
  set_sensitive {
    name  = "authentik.global.env[0].value"
    value = var.phase_authentik_bootstrap_token
  }
  set {
    name  = "authentik.global.env[1].name"
    value = "AUTHENTIK_BOOTSTRAP_PASSWORD"
  }
  set_sensitive {
    name  = "authentik.global.env[1].value"
    value = var.phase_authentik_bootstrap_password
  }

  depends_on = [kubernetes_namespace.authentik, helm_release.postgres, helm_release.redis]
}
