resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name              = "argocd"
  chart             = "${path.module}/../helm/argocd"
  namespace         = kubernetes_namespace.argocd.metadata[0].name
  timeout           = 600
  dependency_update = true

  # ponytail: chart's own values.yaml uses __PLACEHOLDER__ tokens (same
  # convention Tiltfile's string-replace uses), so terraform substitutes
  # the same way instead of introducing a second convention via `set`.
  values = [
    replace(
      replace(
        replace(
          replace(file("${path.module}/../helm/argocd/values.yaml"), "__TS_HOST__", var.ts_host),
          "__ARGOCD_OIDC_CLIENT_ID__", var.argocd_oidc_client_id
        ),
        "__ARGOCD_OIDC_CLIENT_SECRET__", var.argocd_oidc_client_secret
      ),
      "__ADMIN_EMAIL__", var.admin_email
    )
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# ponytail: mirrors Tiltfile's argocd-seed-secretkey — chart renders an empty
# argocd-secret (no data), so ArgoCD generates a random server.secretkey on
# first boot; every pod restart would then invalidate all SSO sessions unless
# this pins it to a stable value after the server exists.
resource "null_resource" "argocd_seed_secretkey" {
  triggers = {
    secret_key = var.argocd_server_secret_key
  }

  provisioner "local-exec" {
    command = "kubectl create secret generic argocd-secret --namespace=argocd --from-literal=server.secretkey=${var.argocd_server_secret_key} --dry-run=client -o yaml | kubectl apply -f - && kubectl rollout restart deployment/argocd-server -n argocd"
  }

  depends_on = [helm_release.argocd]
}
