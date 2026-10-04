resource "kubernetes_namespace" "opencost" {
  count = var.enable_opencost ? 1 : 0
  metadata {
    name = "opencost"
  }
}

resource "helm_release" "opencost" {
  count             = var.enable_opencost ? 1 : 0
  name              = "opencost"
  chart             = "${path.module}/../../../helm/opencost"
  namespace         = kubernetes_namespace.opencost[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/opencost/values.yaml")]

  # this cluster has no Prometheus of its own (unlike internal, which reuses
  # helm/observability's) - turn on the bundled one (Chart.yaml condition).
  set {
    name  = "prometheus.enabled"
    value = "true"
  }

  # this cluster's own docker network can't reach internal's Mimir directly -
  # same host.docker.internal bridge to internal's k3d loadbalancer kubecost
  # used to use (create-cluster.sh/.ps1 + terraform/internal/observability.tf).
  set {
    name  = "prometheus.server.remoteWrite[0].url"
    value = "http://host.docker.internal:${var.mimir_push_port}/api/v1/push"
  }

  set {
    name  = "prometheus.server.global.external_labels.cluster_id"
    value = var.cluster_id
  }

  # in-cluster - opencost queries the bundled prometheus above directly, no
  # bridge needed for reads (only the remoteWrite above needs one).
  set {
    name  = "oc.opencost.prometheus.external.url"
    value = "http://opencost-prometheus-server.${kubernetes_namespace.opencost[0].metadata[0].name}.svc.cluster.local:80"
  }
}
