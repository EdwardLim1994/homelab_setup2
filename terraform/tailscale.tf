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
#     TWO grants — the shared ProxyGroup needs BOTH or apps time out:
#       # reach the proxy node itself
#       { "src": ["autogroup:member"], "dst": ["tag:k8s"], "ip": ["*"] }
#       # reach the per-app Tailscale Services it advertises
#       { "src": ["autogroup:member"],
#         "dst": ["svc:authentik","svc:gitlab","svc:minio","svc:minio-console",
#                 "svc:n8n","svc:sonarqube","svc:nextcloud","svc:argocd",
#                 "svc:grafana","svc:litellm","svc:openwebui"],
#         "ip":  ["*"] }
#     The svc: grant alone is NOT enough — the host netmap gets the service
#     names but not the node backing them, so every <app>.<tailnet>.ts.net
#     connection times out ("unreachable" in list-urls). The tag:k8s grant is
#     what makes the ProxyGroup node a visible peer.
#     And auto-approval so the node can advertise the Services without
#     hand-approving each one on every restart:
#       "autoApprovers": { "services": { "tag:k8s": ["tag:k8s-operator"] } }
#
#  2. Settings -> OAuth clients -> Generate:
#       scopes: Devices/Core = write, Keys/Auth Keys = write,
#               Services = write   (needed for the shared ProxyGroup in
#               tailscale-ingress.tf — HA Ingress is backed by Tailscale
#               Services; without this scope the operator gets 404 on every
#               Ingress: "error creating Tailscale Service: not found (404)")
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
  # ponytail: 300s isn't enough when a -replace has to uninstall first (CRD
  # finalizers on ProxyGroup/Connector drag it out).
  timeout           = 600

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
