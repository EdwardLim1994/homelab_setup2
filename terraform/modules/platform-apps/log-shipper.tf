resource "kubernetes_namespace" "log_shipper" {
  metadata {
    name = "log-shipper"
  }
}

# ponytail: this cluster's own docker network can't reach internal's Loki
# directly - same host.docker.internal bridge pattern opencost.tf uses for
# Mimir (terraform/internal/observability.tf's loki_nodeport Service is the
# other half).
resource "helm_release" "log_shipper" {
  name              = "log-shipper"
  chart             = "${path.module}/../../../helm/log-shipper"
  namespace         = kubernetes_namespace.log_shipper.metadata[0].name
  dependency_update = true
  timeout           = 300

  values = [
    replace(replace(replace(
      file("${path.module}/../../../helm/log-shipper/values.yaml"),
      "__LOKI_PUSH_URL__", "http://host.docker.internal:${var.loki_push_port}/loki/api/v1/push"),
      "__CLUSTER_ID__", var.cluster_id),
      "__TEMPO_PUSH_ENDPOINT__", "host.docker.internal:${var.tempo_push_port}"),
  ]
}
