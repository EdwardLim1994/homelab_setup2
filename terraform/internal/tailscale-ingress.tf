# One tailscale-class Ingress per app, in the app's own namespace. All of them
# attach to a single shared ProxyGroup (below), so the whole homelab is fronted
# by ONE tailnet node instead of one-per-app. Each app still gets its own
# <app>.<tailnet_domain> MagicDNS name + Let's Encrypt cert, served from that
# node.
#
# Why shared: 11 per-app proxies meant 11 tailnet devices, 11 ACME accounts
# (trips Let's Encrypt's "10 new registrations per IP / 3h"), and 11 stale
# devices to prune after every cluster rebuild. One ProxyGroup = one device,
# one ACME account, 11 certs/week (well under LE's 50/week per registered
# domain, and *.ts.net is a public suffix so <tailnet>.ts.net is the
# registrable domain).
#
# ponytail: kubectl_manifest (not kubernetes_ingress_v1) so plan doesn't need
# the backend namespaces/services to exist yet — same reason cert-manager.tf
# uses it. The `.local` Traefik ingresses each chart already creates are left
# in place for LAN access; this is additive.

# ponytail: replicas = 1 — no HA, fine for a homelab. Bump if a proxy restart
# knocking every app offline for ~30s becomes annoying. On first boot this one
# node provisions all 11 dns-01 certs sequentially (a few minutes).
resource "kubectl_manifest" "tailscale_proxygroup" {
  yaml_body = yamlencode({
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyGroup"
    metadata = {
      name = "homelab-ingress"
    }
    spec = {
      type     = "ingress"
      replicas = 1
    }
  })

  depends_on = [helm_release.tailscale_operator]
}

resource "kubectl_manifest" "tailscale_ingress" {
  for_each = local.tailscale_apps

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "ts-${each.key}"
      namespace = each.value.namespace
      annotations = {
        "tailscale.com/proxy-group" = "homelab-ingress"
      }
    }
    spec = {
      ingressClassName = "tailscale"
      defaultBackend = {
        service = {
          name = each.value.service
          port = { number = each.value.port }
        }
      }
      tls = [{ hosts = [each.key] }]
    }
  })

  depends_on = [kubectl_manifest.tailscale_proxygroup]
}
