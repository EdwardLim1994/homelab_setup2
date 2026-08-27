resource "kubernetes_namespace" "litellm" {
  metadata {
    name = "litellm"
  }
}

resource "helm_release" "litellm" {
  name              = "litellm"
  chart             = "${path.module}/../helm/litellm"
  namespace         = kubernetes_namespace.litellm.metadata[0].name
  timeout           = 600
  dependency_update = true

  values = [
    replace(
      replace(
        replace(
          replace(
            replace(
              replace(file("${path.module}/../helm/litellm/values.yaml"), "__TS_HOST__", var.ts_host),
              "__LITELLM_DB_PASSWORD__", var.litellm_db_password
            ),
            "__LITELLM_MASTER_KEY__", var.litellm_master_key
          ),
          "__LITELLM_SALT_KEY__", var.litellm_salt_key
        ),
        "__LITELLM_OIDC_CLIENT_ID__", var.litellm_oidc_client_id
      ),
      "__LITELLM_OIDC_CLIENT_SECRET__", var.litellm_oidc_client_secret
    )
  ]

  depends_on = [kubernetes_namespace.litellm]
}
