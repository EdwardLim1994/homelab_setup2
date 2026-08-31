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

  values = [replace(file("${path.module}/../helm/n8n/values.yaml"), "__TS_HOST__", var.ts_host)]

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
    name  = "flowSeed.apiKey"
    value = var.n8n_api_key
  }

  depends_on = [kubernetes_namespace.n8n, kubernetes_config_map.n8n_oidc_hooks]
}
