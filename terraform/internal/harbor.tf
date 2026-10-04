# ponytail: container registry for generated-app CI pipelines, replacing
# gitlab-registry as the push/pull target. Shared postgres/redis (not the
# chart's bundled ones) and Authentik SSO, same conventions as every other
# internal-cluster app.
resource "kubernetes_namespace" "harbor" {
  metadata {
    name = "harbor"
  }
}

locals {
  harbor_values = replace(replace(replace(
    file("${path.module}/../../helm/harbor/values.yaml"),
    "__HARBOR_ADMIN_PASSWORD__", var.harbor_admin_password),
    "__SHARED_DB_PASSWORD__", var.shared_db_password),
    "__APP_URL__", local.app_url["harbor"])
}

resource "helm_release" "harbor" {
  name              = "harbor"
  chart             = "${path.module}/../../helm/harbor"
  namespace         = kubernetes_namespace.harbor.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [local.harbor_values]

  depends_on = [kubernetes_namespace.harbor, helm_release.postgres, helm_release.redis]
}

# ponytail: no chart-owned Ingress (see helm/harbor/values.yaml) — both
# ingresses point at the chart's single unified `harbor` Service,
# same as every consumer (CI push, image-updater, phase-cluster mirror).
resource "kubectl_manifest" "harbor_ingress_local" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "harbor-local"
      namespace = "harbor"
      annotations = {
        "cert-manager.io/cluster-issuer" = "homelab-ca-issuer"
      }
    }
    spec = {
      ingressClassName = "traefik"
      rules = [{
        host = "harbor.local"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "harbor"
                port = { number = 80 }
              }
            }
          }]
        }
      }]
      tls = [{
        hosts      = ["harbor.local"]
        secretName = "harbor.local-tls"
      }]
    }
  })

  depends_on = [helm_release.harbor]
}

# ponytail: Harbor's OIDC config lives in its own DB (set via API, not a
# helm value) — same "needs a provisioner" situation as Authentik's own app
# providers. oidc_verify_cert=false: Harbor's OIDC is auto-discovery-only (one
# oidc_endpoint, no per-endpoint override like kafka-ui's raw Spring config),
# so its server-side token/userinfo calls land on Authentik's external tailnet
# HTTPS URL (routed in-cluster by coredns.tf's split-horizon rewrite) —
# skipping cert verification for that one internal hop is simpler than
# wiring a CA-bundle mount for a homelab.
resource "null_resource" "harbor_oidc_config" {
  triggers = {
    client_id      = var.harbor_oidc_client_id
    client_secret  = var.harbor_oidc_client_secret
    admin_password = var.harbor_admin_password
    harbor_release = helm_release.harbor.metadata[0].revision
  }

  # ponytail: local-exec runs on the HOST, which can't resolve *.svc.cluster.local
  # — `kubectl run` a one-shot curl pod so the actual request originates
  # inside the cluster network (same trick used to smoke-test this earlier).
  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = <<-EOT
      set -e
      kubectl --context ${var.kube_context} run harbor-oidc-config-$RANDOM --rm -i --restart=Never \
        --image=curlimages/curl -n harbor -- \
        curl -sf -u "admin:${var.harbor_admin_password}" \
          -X PUT "http://harbor.harbor.svc.cluster.local/api/v2.0/configurations" \
          -H "Content-Type: application/json" \
          -d '{
            "auth_mode": "oidc_auth",
            "oidc_name": "authentik",
            "oidc_endpoint": "${local.authentik_url}/application/o/harbor/",
            "oidc_client_id": "${var.harbor_oidc_client_id}",
            "oidc_client_secret": "${var.harbor_oidc_client_secret}",
            "oidc_scope": "openid,profile,email",
            "oidc_verify_cert": false,
            "oidc_auto_onboard": true,
            "oidc_user_claim": "preferred_username"
          }'
    EOT
  }

  depends_on = [helm_release.harbor]
}
