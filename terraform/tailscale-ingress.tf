# One tailscale-class Ingress per app, in the app's own namespace. The operator
# provisions a dedicated tailnet node per Ingress, named after tls.hosts[0], and
# serves it over HTTPS (Let's Encrypt) at <app>.<tailnet_domain>.
#
# ponytail: kubectl_manifest (not kubernetes_ingress_v1) so plan doesn't need
# the backend namespaces/services to exist yet — same reason cert-manager.tf
# uses it. The `.local` Traefik ingresses each chart already creates are left
# in place for LAN access; this is additive.
resource "kubectl_manifest" "tailscale_ingress" {
  for_each = local.tailscale_apps

  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "ts-${each.key}"
      namespace = each.value.namespace
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

  depends_on = [helm_release.tailscale_operator]
}
