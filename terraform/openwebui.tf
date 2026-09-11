resource "kubernetes_namespace" "openwebui" {
  metadata {
    name = "openwebui"
  }
}

# ponytail: mirrors Tiltfile's ca_cert_b64 injection — OpenWebUI needs to
# trust homelab's self-signed CA to make server-side OIDC calls to Authentik
# over Tailscale HTTPS. Separate data source name from mattermost.tf's
# identical one — a data "kubernetes_secret" "homelab_ca" already exists
# there, and resource names must be unique per type per module.
data "kubernetes_secret" "homelab_ca_openwebui" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [null_resource.homelab_ca_ready]
}

resource "kubernetes_secret" "openwebui_homelab_ca" {
  metadata {
    name      = "homelab-ca"
    namespace = kubernetes_namespace.openwebui.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca_openwebui.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.openwebui, data.kubernetes_secret.homelab_ca_openwebui]
}

# ponytail: the n8n-trigger Pipe function (helm/openwebui/functions/n8n_pipe.py)
# is NOT deployed here. OpenWebUI stores functions in its own DB, writable only
# through the UI/API, and the admin API key needed to POST one is itself created
# in the UI — no clean IaC path. It's a one-time paste (Workspace -> Functions ->
# + -> paste -> enable -> set n8n_url valve) and persists on the PVC across
# restarts. See helm/openwebui/functions/README.md. Optional: only needed to
# trigger n8n flows from chat; direct LiteLLM chat works without it.

resource "helm_release" "openwebui" {
  name              = "openwebui"
  chart             = "${path.module}/../helm/openwebui"
  namespace         = kubernetes_namespace.openwebui.metadata[0].name
  # ponytail: ghcr.io/open-webui/open-webui:main is multi-GB (bundled ML
  # deps) — 600s (other apps' default) wasn't enough for a cold pull.
  timeout           = 1200
  dependency_update = true

  values = [
    replace(replace(replace(replace(replace(replace(
      file("${path.module}/../helm/openwebui/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["openwebui"]),
      "__LITELLM_MASTER_KEY__", var.litellm_master_key),
      "__OPENWEBUI_OIDC_CLIENT_ID__", var.openwebui_oidc_client_id),
    "__OPENWEBUI_OIDC_CLIENT_SECRET__", var.openwebui_oidc_client_secret)
  ]

  depends_on = [kubernetes_namespace.openwebui, kubernetes_secret.openwebui_homelab_ca]
}
