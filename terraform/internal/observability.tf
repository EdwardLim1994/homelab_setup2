resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

resource "helm_release" "observability" {
  name              = "observability"
  chart             = "${path.module}/../../helm/observability"
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
        file("${path.module}/../../helm/observability/values.yaml"),
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
      "# dashboards-hash: ${sha1(join(",", [for f in fileset("${path.module}/../../helm/observability/dashboards", "*.json") : filesha1("${path.module}/../../helm/observability/dashboards/${f}")]))}",
    ]),
  ]

  depends_on = [kubernetes_namespace.observability]
}

# ponytail: sit/uat/production sit on separate docker networks and can't
# reach observability-mimir-distributor.observability.svc.cluster.local
# directly - same host.docker.internal bridge as the gitlab-registry mirror
# (create-cluster.sh MIMIR_PUSH_PORT, default 30510, mapped on internal's
# k3d loadbalancer). This NodePort Service is the other half of that bridge -
# same selector as the chart's own mimir-distributor Service, just exposed
# as a fixed NodePort instead of ClusterIP.
resource "kubernetes_service" "mimir_distributor_nodeport" {
  metadata {
    name      = "mimir-distributor-nodeport"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"      = "mimir"
      "app.kubernetes.io/component" = "distributor"
      "app.kubernetes.io/instance"  = "observability"
    }
    port {
      port        = 8080
      target_port = "http-metrics"
      node_port   = var.mimir_push_port
    }
  }
  depends_on = [helm_release.observability]
}

# ponytail: same bridge as mimir_distributor_nodeport above, for
# sit/uat/production's log-shipper (terraform/modules/platform-apps/
# log-shipper.tf) to push pod logs into internal's Loki — SingleBinary mode,
# so the chart's own "loki" component label covers both write+read, no
# separate distributor to target.
resource "kubernetes_service" "loki_nodeport" {
  metadata {
    name      = "loki-nodeport"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"      = "loki"
      "app.kubernetes.io/component" = "single-binary"
      "app.kubernetes.io/instance"  = "observability"
    }
    port {
      port        = 3100
      target_port = "http-metrics"
      node_port   = var.loki_push_port
    }
  }
  depends_on = [helm_release.observability]
}

# ponytail: same bridge direction as loki_nodeport above, for
# sit/uat/production's log-shipper to push traces into internal's Tempo —
# grafana/tempo's default monolithic mode is one Deployment, no
# component label to narrow on (unlike mimir/loki above). target_port by
# number, not name — the chart's own OTLP grpc container port, not
# guessing its Service port name.
resource "kubernetes_service" "tempo_nodeport" {
  metadata {
    name      = "tempo-nodeport"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"     = "tempo"
      "app.kubernetes.io/instance" = "observability"
    }
    port {
      port        = 4317
      target_port = 4317
      node_port   = var.tempo_push_port
    }
  }
  depends_on = [helm_release.observability]
}
