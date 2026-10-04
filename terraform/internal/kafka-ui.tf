resource "kubernetes_namespace" "kafka_ui" {
  metadata {
    name = "kafka-ui"
  }
}

# ponytail: __PLACEHOLDER__ -> secret substitution, one replace() per key.
locals {
  kafka_ui_values = replace(replace(replace(replace(
    file("${path.module}/../../helm/kafka-ui/values.yaml"),
    "__AUTHENTIK_URL__", local.authentik_url),
    "__APP_URL__", local.app_url["kafka-ui"]),
    "__KAFKA_UI_OIDC_CLIENT_ID__", var.kafka_ui_oidc_client_id),
  "__KAFKA_UI_OIDC_CLIENT_SECRET__", var.kafka_ui_oidc_client_secret)
}

resource "helm_release" "kafka_ui" {
  name              = "kafka-ui"
  chart             = "${path.module}/../../helm/kafka-ui"
  namespace         = kubernetes_namespace.kafka_ui.metadata[0].name
  timeout           = 300
  dependency_update = true

  values = [local.kafka_ui_values]

  depends_on = [kubernetes_namespace.kafka_ui]
}
