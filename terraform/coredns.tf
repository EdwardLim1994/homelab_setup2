# Split-horizon DNS for Authentik.
#
# Apps that do OIDC *discovery* server-side (MinIO's only knob is CONFIG_URL;
# it can't split browser vs backend endpoints the way gitlab/grafana/litellm
# do) must fetch https://authentik.<tailnet>.ts.net from inside the cluster.
# That name resolves to the Tailscale Service VIP, which pods have no route to
# — so the fetch times out and OIDC silently stays disabled.
#
# Fix: in-cluster, rewrite authentik.<tailnet> to traefik, and give traefik a
# vhost for it with a homelab-CA cert. Browser traffic is unaffected — it still
# uses the real external name over Tailscale. Consuming apps trust the homelab
# CA (see kubernetes_secret.minio_homelab_ca in minio.tf, mattermost.tf).
#
# Terraform-only: the Tilt path reaches apps via *.local + port-forwards and
# never uses the tailnet hostname, so there is no Tiltfile counterpart (same as
# terraform/tailscale-ingress.tf).

resource "kubernetes_config_map" "coredns_custom" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }
  # k3s CoreDNS imports /etc/coredns/custom/*.override inside its server block.
  data = {
    "authentik.override" = "rewrite name exact authentik.${local.tailnet_domain} traefik.kube-system.svc.cluster.local"
  }
}

# CoreDNS only reads coredns-custom on (re)start.
resource "null_resource" "coredns_reload" {
  triggers = {
    rule = kubernetes_config_map.coredns_custom.data["authentik.override"]
  }
  provisioner "local-exec" {
    command = "kubectl -n kube-system rollout restart deploy/coredns"
  }
  depends_on = [kubernetes_config_map.coredns_custom]
}

# traefik vhost for the tailnet hostname, backed by authentik-server (plain
# HTTP :80), TLS terminated with a homelab-CA cert. The chart's own Ingress
# keeps serving authentik.local; traefik merges the two by host.
resource "kubectl_manifest" "authentik_internal_ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "authentik-tailnet-internal"
      namespace = "authentik"
      annotations = {
        "cert-manager.io/cluster-issuer" = "homelab-ca-issuer"
      }
    }
    spec = {
      ingressClassName = "traefik"
      rules = [{
        host = "authentik.${local.tailnet_domain}"
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend  = { service = { name = "authentik-server", port = { number = 80 } } }
          }]
        }
      }]
      tls = [{
        hosts      = ["authentik.${local.tailnet_domain}"]
        secretName = "authentik-tailnet-tls"
      }]
    }
  })

  depends_on = [helm_release.authentik]
}
