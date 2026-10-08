resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# ponytail: argocd-server does OIDC discovery server-side against Authentik's
# tailnet HTTPS URL (coredns.tf rewrites it to in-cluster traefik + a
# homelab-CA cert) — needs to trust that CA. Same read-and-copy pattern as
# minio.tf / openwebui.tf; separate data source name, resource names must be
# unique per type per module.
data "kubernetes_secret" "homelab_ca_argocd" {
  metadata {
    name      = "homelab-ca-secret"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  depends_on = [null_resource.homelab_ca_ready]
}

resource "kubernetes_secret" "argocd_homelab_ca" {
  metadata {
    name      = "homelab-ca"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }
  data = {
    "ca.crt" = data.kubernetes_secret.homelab_ca_argocd.data["tls.crt"]
  }
  depends_on = [kubernetes_namespace.argocd, data.kubernetes_secret.homelab_ca_argocd]
}

resource "helm_release" "argocd" {
  name              = "argocd"
  chart             = "${path.module}/../../helm/argocd"
  namespace         = kubernetes_namespace.argocd.metadata[0].name
  timeout           = 600
  dependency_update = true

  # ponytail: chart's own values.yaml uses __PLACEHOLDER__ tokens — terraform
  # substitutes via replace() instead of introducing a second convention via `set`.
  values = [
    replace(replace(replace(replace(replace(replace(replace(
      file("${path.module}/../../helm/argocd/values.yaml"),
      "__TS_HOST__", var.ts_host),
      "__AUTHENTIK_URL__", local.authentik_url),
      "__APP_URL__", local.app_url["argocd"]),
      "__ARGOCD_OIDC_CLIENT_ID__", var.argocd_oidc_client_id),
      "__ARGOCD_OIDC_CLIENT_SECRET__", var.argocd_oidc_client_secret),
    "__ADMIN_EMAIL__", var.admin_email),
    "__ARGOCD_TOKEN__", var.argocd_token),
  ]

  depends_on = [kubernetes_namespace.argocd, kubernetes_secret.argocd_homelab_ca]
}

# ponytail: image-updater's registries.conf `credentials: secret:...#creds`
# expects one key holding "user:pass" — Harbor's admin account, reused rather
# than minting a scoped robot account for one consumer.
resource "kubernetes_secret" "argocd_image_updater_registry" {
  metadata {
    name      = "argocd-image-updater-registry"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }
  data = {
    creds = "admin:${var.harbor_admin_password}"
  }
  depends_on = [kubernetes_namespace.argocd]
}

# ponytail: ArgoCD had zero git credentials registered -- found live when
# the first-ever generated project's Applications all synced
# ComparisonError: authentication required. url is a prefix match
# (argocd.argoproj.io/secret-type: repo-creds), so this covers every
# project's repo on this one GitLab instance, not just hr-portal-dryrun --
# no new secret needed as future kickoffs create new projects/repos.
# GitLab accepts any non-empty username with a PAT as the password over
# HTTP basic auth (same var.omp_gitlab_token every omp-agent pod already
# uses for `glab auth login`).
resource "kubernetes_secret" "argocd_gitlab_repo_creds" {
  metadata {
    name      = "argocd-gitlab-repo-creds"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }
  data = {
    type     = "git"
    url      = "http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/"
    username = "oauth2"
    password = var.omp_gitlab_token
  }
  depends_on = [kubernetes_namespace.argocd]
}

# ponytail: chart renders an empty argocd-secret (no data), so ArgoCD
# generates a random server.secretkey on first boot; every pod restart would
# then invalidate all SSO sessions unless
# this pins it to a stable value after the server exists.
resource "null_resource" "argocd_seed_secretkey" {
  triggers = {
    secret_key = var.argocd_server_secret_key
  }

  provisioner "local-exec" {
    command = "kubectl --context ${var.kube_context} create secret generic argocd-secret --namespace=argocd --from-literal=server.secretkey=${var.argocd_server_secret_key} --dry-run=client -o yaml | kubectl --context ${var.kube_context} apply -f - && kubectl --context ${var.kube_context} rollout restart deployment/argocd-server -n argocd"
  }

  depends_on = [helm_release.argocd]
}
