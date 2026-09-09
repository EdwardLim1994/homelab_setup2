resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
  }
}

resource "kubernetes_config_map" "n8n_oidc_hooks" {
  metadata {
    name      = "n8n-oidc-hooks"
    namespace = kubernetes_namespace.n8n.metadata[0].name
  }
  data = {
    "hooks.js" = file("${path.module}/../helm/n8n/hooks.js")
  }
  depends_on = [kubernetes_namespace.n8n]
}

resource "helm_release" "n8n" {
  name              = "n8n"
  chart             = "${path.module}/../helm/n8n"
  namespace         = kubernetes_namespace.n8n.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(replace(replace(
      file("${path.module}/../helm/n8n/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
    "__APP_URL__", local.app_url["n8n"]),
  ]

  set_sensitive {
    name  = "n8n.encryptionKey"
    value = var.n8n_encryption_key
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.OIDC_CLIENT_ID"
    value = var.n8n_oidc_client_id
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.OIDC_CLIENT_SECRET"
    value = var.n8n_oidc_client_secret
  }

  set_sensitive {
    name  = "n8n.main.extraEnvVars.LITELLM_MASTER_KEY"
    value = var.litellm_master_key
  }

  set_sensitive {
    name  = "n8n.externalPostgresql.password"
    value = var.n8n_db_password
  }

  set_sensitive {
    name  = "postgres.password"
    value = var.n8n_db_password
  }

  # ponytail: flow seeding + owner setup + API-key minting all moved to the
  # ansible runner — `scripts/ansible-run.sh n8n`.

  depends_on = [kubernetes_namespace.n8n, kubernetes_config_map.n8n_oidc_hooks]
}
