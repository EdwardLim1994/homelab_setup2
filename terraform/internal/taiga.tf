# ponytail: ticket/wiki tracker replacing GitLab issues+wiki for the SDLC
# flows (replaces OpenProject — Community Edition hard-gates every custom
# SSO provider behind an Enterprise license, confirmed in its own source and
# docs; Taiga is AGPL, no license gate, and has first-party GitLab webhook
# integration for the compliance activity trail — see AGENTS.md's "GitLab
# compliance history"). Shared postgres, own rabbitmq (first broker chart in
# this repo). No official Helm chart exists for Taiga — helm/taiga is
# hand-rolled, same convention as helm/omp/helm/litellm.
resource "kubernetes_namespace" "taiga" {
  metadata {
    name = "taiga"
  }
}

# ponytail: official taiga-back has no OIDC support — the only gap is one
# pip package, baked here rather than at chart-apply time. Mirrors
# terraform/internal/omp-agent.tf's null_resource + local-exec pattern
# exactly (build+push to the local k3d registry, gated by a Dockerfile hash
# trigger).
resource "null_resource" "taiga_back_image" {
  triggers = {
    dockerfile = filesha1("${path.module}/../../helm/taiga/Dockerfile")
  }

  provisioner "local-exec" {
    working_dir = abspath("${path.module}/../../helm/taiga")
    command     = "docker build -t localhost:5111/taiga-back-oidc:dev . && docker push localhost:5111/taiga-back-oidc:dev"
  }
}

# ponytail: official taiga-front has no OIDC login button either — it's a
# separate front/ plugin bundle from taiga-contrib-oidc-auth (old
# gulp/jade/coffee toolchain, still builds clean on node:16 — verified).
# Same build+push-to-local-registry pattern as the back image above.
resource "null_resource" "taiga_front_image" {
  triggers = {
    dockerfile = filesha1("${path.module}/../../helm/taiga/Dockerfile.front")
  }

  provisioner "local-exec" {
    working_dir = abspath("${path.module}/../../helm/taiga")
    command     = "docker build -f Dockerfile.front -t localhost:5111/taiga-front-oidc:dev . && docker push localhost:5111/taiga-front-oidc:dev"
  }
}

locals {
  taiga_values = replace(replace(replace(replace(replace(replace(replace(
    file("${path.module}/../../helm/taiga/values.yaml"),
    "__APP_URL_HOST__", trimprefix(local.app_url["taiga"], "https://")),
    "__AUTHENTIK_URL__", local.authentik_url),
    "__TAIGA_OIDC_CLIENT_ID__", var.taiga_oidc_client_id),
    "__TAIGA_OIDC_CLIENT_SECRET__", var.taiga_oidc_client_secret),
    "__TAIGA_ADMIN_PASSWORD__", var.taiga_admin_password),
    "__TAIGA_SECRET_KEY__", var.taiga_secret_key),
    "__TAIGA_RABBITMQ_PASSWORD__", var.taiga_rabbitmq_password)
  taiga_values2 = replace(replace(local.taiga_values,
    "__SHARED_DB_PASSWORD__", var.shared_db_password),
    "__ADMIN_EMAIL__", var.admin_email)
}

resource "helm_release" "taiga" {
  name              = "taiga"
  chart             = "${path.module}/../../helm/taiga"
  namespace         = kubernetes_namespace.taiga.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [local.taiga_values2]

  # ponytail: the helm provider doesn't hash local chart template files (only
  # values) — an edit to e.g. templates/back.yaml wouldn't redeploy on its
  # own. Mirrors helm_release.n8n/helm_release.ansible's identical fix.
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/taiga", "**") : filesha1("${path.module}/../../helm/taiga/${f}")
    ]))
  }

  depends_on = [kubernetes_namespace.taiga, helm_release.postgres, null_resource.taiga_back_image, null_resource.taiga_front_image]
}

resource "kubectl_manifest" "taiga_ingress_local" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "taiga-local"
      namespace = "taiga"
      annotations = {
        "cert-manager.io/cluster-issuer" = "homelab-ca-issuer"
      }
    }
    spec = {
      ingressClassName = "traefik"
      rules = [{
        host = "taiga.local"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "taiga-gateway"
                port = { number = 80 }
              }
            }
          }]
        }
      }]
      tls = [{
        hosts      = ["taiga.local"]
        secretName = "taiga.local-tls"
      }]
    }
  })

  depends_on = [helm_release.taiga]
}
