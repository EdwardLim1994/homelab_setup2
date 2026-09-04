# Tailscale Kubernetes Operator — replaces the old host-side `tailscale serve`
# chain (and the `scripts/*/port-forward-terraform-apps.*` fallback). Each app
# opts in with a `tailscale`-class
# Ingress (see terraform/tailscale-ingress.tf) and gets its own MagicDNS name
# on the tailnet, HTTPS via Let's Encrypt, no host process to babysit.
#
# ONE-TIME SETUP in the Tailscale admin console (can't be terraformed without
# an already-existing key to bootstrap with):
#
#  1. Tailnet ACL — add:
#       "tagOwners": {
#         "tag:k8s-operator": [],
#         "tag:k8s":          ["tag:k8s-operator"]
#       }
#     and a grant letting your user reach the tagged nodes, e.g.
#       { "src": ["autogroup:member"], "dst": ["tag:k8s"], "ip": ["*"] }
#
#  2. Settings -> OAuth clients -> Generate:
#       scopes: Devices/Core = write, Keys/Auth Keys = write
#       tags:   tag:k8s-operator
#     Put the id/secret in .env:
#       TF_VAR_tailscale_oauth_client_id=...
#       TF_VAR_tailscale_oauth_client_secret=...
#
#  3. Tailnet must have HTTPS + MagicDNS enabled (already true here — the old
#     `tailscale serve --https` setup depended on it).

resource "kubernetes_namespace" "tailscale" {
  metadata {
    name = "tailscale"
  }
}

resource "helm_release" "tailscale_operator" {
  name              = "tailscale-operator"
  chart             = "${path.module}/../helm/tailscale-operator"
  namespace         = kubernetes_namespace.tailscale.metadata[0].name
  dependency_update = true
  timeout           = 300

  values = [file("${path.module}/../helm/tailscale-operator/values.yaml")]

  set_sensitive {
    name  = "tailscale-operator.oauth.clientId"
    value = var.tailscale_oauth_client_id
  }

  set_sensitive {
    name  = "tailscale-operator.oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }

  depends_on = [kubernetes_namespace.tailscale]
}
