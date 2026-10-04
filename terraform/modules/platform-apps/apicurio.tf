resource "kubernetes_namespace" "apicurio" {
  count = var.enable_apicurio ? 1 : 0
  metadata {
    name = "apicurio"
  }
}

resource "helm_release" "apicurio" {
  count             = var.enable_apicurio ? 1 : 0
  name              = "apicurio-registry"
  chart             = "${path.module}/../../../helm/apicurio-registry"
  namespace         = kubernetes_namespace.apicurio[0].metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../../helm/apicurio-registry/values.yaml")]
}

# ponytail: same reversed NodePort bridge as kafka.tf's kafka_external —
# GitLab CI (internal cluster) pushes schemas here per environment
# (devops-engineer/SKILL.md's push-schemas:sit/uat/production jobs).
# var.apicurio_nodeport must match the `-p` mapping create-cluster.sh adds
# for this cluster name. Selector/port copied from the vendored chart's own
# templates/service-registry.yaml (apicurio-registry.selectorLabels +
# component=registry, port 8080) — that chart has no service.type override.
resource "kubernetes_service" "apicurio_external" {
  count = var.enable_apicurio ? 1 : 0
  metadata {
    name      = "apicurio-external"
    namespace = kubernetes_namespace.apicurio[0].metadata[0].name
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"     = "apicurio-registry"
      "app.kubernetes.io/instance" = "apicurio-registry"
      "app.kubernetes.io/component" = "registry"
    }
    port {
      port        = 8080
      target_port = 8080
      node_port   = var.apicurio_nodeport
    }
  }
}
