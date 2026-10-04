# ponytail: only phase clusters get a terraform-managed traefik - internal
# keeps k3s's bundled one untouched (existing cert-manager/coredns wiring
# depends on it). Phase clusters must have k3s's own traefik add-on disabled
# at cluster creation (create-cluster.sh --k3s-arg disable=traefik) or the
# two LoadBalancers fight over ports 80/443.

resource "kubernetes_namespace" "traefik" {
  count = var.enable_traefik ? 1 : 0
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  count             = var.enable_traefik ? 1 : 0
  name              = "traefik"
  chart             = "${path.module}/../../../helm/traefik"
  namespace         = kubernetes_namespace.traefik[0].metadata[0].name
  dependency_update = true
  timeout           = 300

  values = [file("${path.module}/../../../helm/traefik/values.yaml")]
}
