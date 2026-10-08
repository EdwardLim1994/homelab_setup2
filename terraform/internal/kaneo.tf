# ponytail: ticket tracker replacing Taiga — MIT, single container, native
# OIDC, and a real bidirectional GitLab integration (merged upstream
# 2026-09-26) vs Taiga's one-way compliance webhook. Wiki moves back to
# GitLab's own per-project wiki (Kaneo has none) — see AGENT.md's "Kaneo"
# section. Shared postgres + MinIO (S3), no bundled Redis. No official Helm
# chart published to a repo/OCI registry — helm/kaneo is hand-rolled, same
# convention as helm/taiga was.
resource "kubernetes_namespace" "kaneo" {
  metadata {
    name = "kaneo"
  }
}

locals {
  kaneo_values = replace(replace(replace(replace(replace(
    file("${path.module}/../../helm/kaneo/values.yaml"),
    "__APP_URL_HOST__", trimprefix(local.app_url["kaneo"], "https://")),
    "__AUTHENTIK_URL__", local.authentik_url),
    "__KANEO_OIDC_CLIENT_ID__", var.kaneo_oidc_client_id),
    "__KANEO_OIDC_CLIENT_SECRET__", var.kaneo_oidc_client_secret),
    "__KANEO_AUTH_SECRET__", var.kaneo_auth_secret)
  kaneo_values2 = replace(replace(local.kaneo_values,
    "__SHARED_DB_PASSWORD__", var.shared_db_password),
    "__MINIO_ROOT_PASSWORD__", var.minio_root_password)
}

resource "helm_release" "kaneo" {
  name              = "kaneo"
  chart             = "${path.module}/../../helm/kaneo"
  namespace         = kubernetes_namespace.kaneo.metadata[0].name
  timeout           = 300
  dependency_update = true

  values = [local.kaneo_values2]

  # ponytail: the helm provider doesn't hash local chart template files —
  # mirrors helm_release.taiga's identical fix (see git history).
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/kaneo", "**") : filesha1("${path.module}/../../helm/kaneo/${f}")
    ]))
  }

  depends_on = [kubernetes_namespace.kaneo, helm_release.postgres, helm_release.minio]
}

resource "kubectl_manifest" "kaneo_ingress_local" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "kaneo-local"
      namespace = "kaneo"
      annotations = {
        "cert-manager.io/cluster-issuer" = "homelab-ca-issuer"
      }
    }
    spec = {
      ingressClassName = "traefik"
      rules = [{
        host = "kaneo.local"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "kaneo"
                port = { number = 5173 }
              }
            }
          }]
        }
      }]
      tls = [{
        hosts      = ["kaneo.local"]
        secretName = "kaneo.local-tls"
      }]
    }
  })

  depends_on = [helm_release.kaneo]
}
