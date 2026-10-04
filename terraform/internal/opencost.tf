resource "kubernetes_namespace" "opencost" {
  metadata {
    name = "opencost"
  }
}

# ponytail: no bundled Prometheus here (unlike sit/uat/production's
# opencost.tf) — internal already has one (helm/observability's bundled
# kube-prometheus stack scrapes kube-state-metrics/cadvisor/node-exporter and
# remote_writes into Mimir), so opencost just queries that via Mimir's
# Prometheus-compatible query-frontend endpoint. No UI either — cost data
# surfaces through the Grafana dashboard
# (helm/observability/dashboards/opencost.json) instead of a standalone
# tailscale-exposed UI the way kubecost's native UI needed.
resource "helm_release" "opencost" {
  name              = "opencost"
  chart             = "${path.module}/../../helm/opencost"
  namespace         = kubernetes_namespace.opencost.metadata[0].name
  dependency_update = true
  timeout           = 600

  values = [file("${path.module}/../../helm/opencost/values.yaml")]

  set {
    name  = "oc.opencost.prometheus.external.url"
    value = "http://observability-mimir-query-frontend.observability.svc.cluster.local:8080/prometheus"
  }

  depends_on = [kubernetes_namespace.opencost, helm_release.observability]
}
