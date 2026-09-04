resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

resource "helm_release" "observability" {
  name              = "observability"
  chart             = "${path.module}/../helm/observability"
  namespace         = kubernetes_namespace.observability.metadata[0].name
  timeout           = 900
  dependency_update = true
  # ponytail: mimir subcomponents can crashloop on first boot (resource
  # requests/kafka startup ordering) independent of terraform — don't block
  # apply 15min on app-level health, k8s reconciles on its own.
  wait = false

  values = [
    join("\n", [
      replace(replace(replace(replace(replace(replace(replace(replace(
        file("${path.module}/../helm/observability/values.yaml"),
        "__TS_HOST__", var.ts_host),
        "__TAILNET_DOMAIN__", local.tailnet_domain),
        "__AUTHENTIK_URL__", local.authentik_url),
        "__APP_URL__", local.app_url["grafana"]),
        "__GRAFANA_ADMIN_PASSWORD__", var.grafana_admin_password),
        "__GRAFANA_OIDC_CLIENT_ID__", var.grafana_oidc_client_id),
        "__GRAFANA_OIDC_CLIENT_SECRET__", var.grafana_oidc_client_secret),
      "__ADMIN_EMAIL__", var.admin_email),
      # ponytail: the helm provider doesn't hash dashboards/*.json (loaded via
      # .Files.Get in templates/dashboards.yaml), so editing a dashboard alone
      # produces "No changes". This trailing YAML comment folds their content
      # hash into the values string -> a dashboard edit now triggers the upgrade.
      "# dashboards-hash: ${sha1(join(",", [for f in fileset("${path.module}/../helm/observability/dashboards", "*.json") : filesha1("${path.module}/../helm/observability/dashboards/${f}")]))}",
    ]),
  ]

  depends_on = [kubernetes_namespace.observability]
}
