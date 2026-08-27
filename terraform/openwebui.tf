resource "kubernetes_namespace" "openwebui" {
  metadata {
    name = "openwebui"
  }
}

# ponytail: mirrors Tiltfile's ca_cert_b64 injection — OpenWebUI needs to
# trust homelab's self-signed CA to make server-side OIDC calls to Authentik
# over Tailscale HTTPS.
data "kubernetes_secret" "homelab_ca" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [kubectl_manifest.homelab_ca]
}

resource "kubernetes_secret" "openwebui_homelab_ca" {
  metadata {
    name      = "homelab-ca"
    namespace = kubernetes_namespace.openwebui.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.openwebui, data.kubernetes_secret.homelab_ca]
}

resource "helm_release" "openwebui" {
  name              = "openwebui"
  chart             = "${path.module}/../helm/openwebui"
  namespace         = kubernetes_namespace.openwebui.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(
      replace(
        replace(
          replace(file("${path.module}/../helm/openwebui/values.yaml"), "__TS_HOST__", var.ts_host),
          "__LITELLM_MASTER_KEY__", var.litellm_master_key
        ),
        "__OPENWEBUI_OIDC_CLIENT_ID__", var.openwebui_oidc_client_id
      ),
      "__OPENWEBUI_OIDC_CLIENT_SECRET__", var.openwebui_oidc_client_secret
    )
  ]

  depends_on = [kubernetes_namespace.openwebui, kubernetes_secret.openwebui_homelab_ca]
}
