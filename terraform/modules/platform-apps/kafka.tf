resource "kubernetes_namespace" "kafka" {
  count = var.enable_kafka ? 1 : 0
  metadata {
    name = "kafka"
  }
}

resource "helm_release" "kafka" {
  count             = var.enable_kafka ? 1 : 0
  name              = "kafka"
  chart             = "${path.module}/../../../helm/kafka"
  namespace         = kubernetes_namespace.kafka[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/kafka/values.yaml")]
}

# ponytail: internal's kafka-ui needs to reach this cluster's kafka, but sit/
# uat/production each sit on their own Docker network with no route from
# internal's — same host.docker.internal NodePort bridge as the gitlab-
# registry mirror / opencost->Mimir push (scripts/*/create-cluster.sh), just
# reversed: THIS cluster exposes kafka via a NodePort on ITS OWN k3d
# loadbalancer instead of internal's. var.kafka_nodeport must match the
# `-p` mapping create-cluster.sh adds for this cluster name.
resource "kubernetes_service" "kafka_external" {
  count = var.enable_kafka ? 1 : 0
  metadata {
    name      = "kafka-external"
    namespace = kubernetes_namespace.kafka[0].metadata[0].name
  }
  spec {
    type     = "NodePort"
    selector = { app = "kafka" }
    port {
      port        = 9092
      target_port = 9092
      node_port   = var.kafka_nodeport
    }
  }
}
