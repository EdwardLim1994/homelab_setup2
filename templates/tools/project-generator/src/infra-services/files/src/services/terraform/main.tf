resource "kubernetes_namespace" "infra" {
  metadata {
    name = var.namespace
  }
}

# Runs `helm dependency update` for every chart that wraps an upstream dependency. Triggers only
# when a Chart.yaml changes — stable on repeated applies when charts are unchanged.
resource "terraform_data" "helm_dep_update" {
  triggers_replace = [
    filemd5("${path.module}/../traefik/helm/Chart.yaml"),
    filemd5("${path.module}/../authentik/helm/Chart.yaml"),
    filemd5("${path.module}/../openbao/helm/Chart.yaml"),
    filemd5("${path.module}/../cert-manager/helm/Chart.yaml"),
    filemd5("${path.module}/../unleash/helm/Chart.yaml"),
    filemd5("${path.module}/../apollo/helm/Chart.yaml"),
  ]

  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-EOT
      $charts = @(
        "${path.module}/../traefik/helm",
        "${path.module}/../authentik/helm",
        "${path.module}/../openbao/helm",
        "${path.module}/../cert-manager/helm",
        "${path.module}/../unleash/helm",
        "${path.module}/../apollo/helm"
      )
      foreach ($chart in $charts) {
        helm dependency update $chart
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      }
    EOT
  }
}

# traefik installs separately (not in the for_each below) so the rest of the services can
# depend_on it — minio/monitoring's charts look up services/traefik/helm/templates/
# web-8080-service.yaml's ClusterIP via Helm's `lookup` at template-render time (to bake
# "authentik.lan" into their pod hostAliases, see their statefulset.yaml comments), and `lookup`
# has no retry: if traefik doesn't exist yet at that exact moment, it silently falls back to
# 127.0.0.1 and stays wrong for the pod's whole lifetime — no error, just a login that fails with
# "failed to retrieve token" (grafana) or never offers SSO at all (minio). Without this
# depends_on, the for_each's own parallelism raced this on every from-scratch apply.
resource "helm_release" "traefik" {
  name      = "traefik"
  chart     = "${path.module}/../traefik/helm"
  namespace = kubernetes_namespace.infra.metadata[0].name
  wait      = false
  depends_on = [terraform_data.helm_dep_update]
}

# Deploys each services/<name>/helm chart as-is — one copy of each service's manifests to
# maintain, applied here and nowhere else.
locals {
  services = toset([
    "apicurio-registry",
    "authentik",
    "kafka",
    "meilisearch",
    "minio",
    "monitoring",
    "unleash",
  ])

  # Every one of these is duplicated by hand across two independent Helm releases today (see
  # each app's own values.yaml — "must match services/authentik/helm/values.yaml's
  # <app>OidcClientSecret"). Only meaningful on a non-dev cluster (see the set_sensitive blocks
  # below) — dev keeps the hand-typed matched placeholders already in each chart's values.yaml,
  # unchanged.
  oidc_secret_overrides = {
    authentik = {
      "minioOidcClientSecret"                      = random_password.minio_oidc_client_secret.result
      "grafanaOidcClientSecret"                    = random_password.grafana_oidc_client_secret.result
      "authentik.authentik.secret_key"             = var.authentik_secret_key
      "authentik.authentik.postgresql.password"    = var.authentik_postgres_password
      "authentik.postgresql.auth.password"         = var.authentik_postgres_password
      "authentik.postgresql.auth.postgresPassword" = var.authentik_postgres_password
      # Helm doesn't merge list overrides element-wise — overriding a single index/field of a
      # list that the chart's own values.yaml also populates (global.env, here) replaces the
      # *entire* list with only what's given via --set, silently dropping every other field
      # (including "name", which the Deployment's env entries require) and every other list
      # element. Every field of every element has to be repeated here for the same reason.
      "authentik.global.env[0].name"               = "AUTHENTIK_BOOTSTRAP_PASSWORD"
      "authentik.global.env[0].value"               = var.authentik_bootstrap_password
      "authentik.global.env[1].name"               = "AUTHENTIK_BOOTSTRAP_EMAIL"
      "authentik.global.env[1].value"              = "akadmin@authentik.local"
      "authentik.global.env[2].name"               = "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS"
      "authentik.global.env[2].value"              = "0.0.0.0/0"
    }
    minio = {
      "oidcClientSecret" = random_password.minio_oidc_client_secret.result
    }
    monitoring = {
      "grafana.oidcClientSecret" = random_password.grafana_oidc_client_secret.result
    }
  }
}

# Cheap, side-effect-free — always created regardless of environment (referencing them from a
# count/for_each = 0 resource in a dev apply would itself be a plan-time error, not just a no-op).
# Only actually used, via oidc_secret_overrides above, when environment != "dev".
resource "random_password" "minio_oidc_client_secret" {
  length  = 32
  special = false
}
resource "random_password" "grafana_oidc_client_secret" {
  length  = 32
  special = false
}

resource "helm_release" "service" {
  for_each = local.services

  name      = each.key
  chart     = "${path.module}/../${each.key}/helm"
  namespace = kubernetes_namespace.infra.metadata[0].name
  # Don't block apply on pod readiness — on a cold node that's routinely 10-15min, and every
  # cancelled/killed wait leaves the release's Helm secret stuck in pending-install, which then
  # blocks all future installs/upgrades until manually cleared. Check `kubectl get pods` instead.
  wait    = false
  timeout = 300

  # Chart's own values.yaml (dev-mode defaults, safe to commit) always applies first. On any
  # non-dev apply (sit/uat/staging/prod), each chart's values-nondev.yaml — where one exists —
  # layers on top as a Helm values file, same mechanism as `helm upgrade -f values.yaml -f
  # values-nondev.yaml`. Nothing today differs between the four real clusters, so they share one
  # file rather than one each. Charts with nothing non-dev differs on (kafka, meilisearch, ...)
  # simply have no values-nondev.yaml and this is a no-op for them.
  #
  # values-tailscale.yaml (authentik, monitoring only) layers on top unconditionally in dev —
  # no LAN/tailscale toggle. Points Grafana's OAuth
  # authUrl/rootUrl at the tailscale tunnel scripts/port-forward.sh opens instead of
  # "authentik.lan"/"grafana.lan", which only resolve on-LAN — off-LAN clients (e.g. a phone or
  # tablet on the tailnet but not the LAN) hit an unreachable host without this.
  values = concat(
    var.tailscale && fileexists("${path.module}/../${each.key}/helm/values-tailscale.yaml")
    ? [templatefile("${path.module}/../${each.key}/helm/values-tailscale.yaml", {
        tailscale_hostname = var.tailscale_hostname
      })]
    : [],
    var.environment != "dev" && fileexists("${path.module}/../${each.key}/helm/values-nondev.yaml")
    ? [file("${path.module}/../${each.key}/helm/values-nondev.yaml")]
    : []
  )

  # Real secrets, never committed — only meaningful (and only required) for a non-dev cluster.
  dynamic "set_sensitive" {
    for_each = var.environment != "dev" ? lookup(local.oidc_secret_overrides, each.key, {}) : {}
    content {
      name  = set_sensitive.key
      value = set_sensitive.value
    }
  }

  # Every chart's own values.yaml hardcodes `namespace: infra` as a plain value (not templated
  # off the release's own --namespace), used for cross-references baked into its templates (e.g.
  # ServiceAccount annotations, `http://authentik-server.<namespace>.svc` DNS names) — the `namespace =`
  # argument above only controls which k8s Namespace object the release's own resources land in,
  # it does NOT flow into that value. Without this override, every helm_release here still
  # cross-references the literal "infra" namespace regardless of var.namespace, breaking anything
  # other than the single-namespace default (surfaces as "no matches for kind Certificate" /
  # wrong-namespace DNS lookups on a second namespace/cluster deploy).
  set {
    name  = "namespace"
    value = kubernetes_namespace.infra.metadata[0].name
  }

  depends_on = [helm_release.traefik]
}

# Not in the for_each above — services/openbao/helm is a dependency-chart wrapper (see its own
# Chart.yaml), not a hand-rolled chart with a hardcoded `namespace: infra` value the way every
# for_each member above needs overridden; `namespace = ` below is enough on its own, no `set`
# block needed. KV v2 store for apps/servers/*'s own app-level secrets only — never used for
# Postgres/Redis credentials, which stay static (see var.authentik_postgres_password and
# apps/terraform's own random_password.db/redis) after this repo's earlier Vault removal.
resource "helm_release" "openbao" {
  name      = "openbao"
  chart     = "${path.module}/../openbao/helm"
  namespace = kubernetes_namespace.infra.metadata[0].name
  wait      = false
  timeout   = 300

  values = (
    var.environment != "dev" && fileexists("${path.module}/../openbao/helm/values-nondev.yaml")
    ? [file("${path.module}/../openbao/helm/values-nondev.yaml")]
    : []
  )

  depends_on = [helm_release.traefik]
}

# Not in the for_each above. cert-manager itself, and its Issuer/Certificate config, are two
# separate helm_releases (not one) deliberately: applying a CRD and a custom resource of that
# CRD's kind in the *same* release races the API server (it hasn't finished registering the new
# kind yet), which is exactly the "no matches for kind Certificate/Issuer" error this used to hit
# as one release. Two terraform-sequenced releases guarantee a real apply boundary in between.
resource "helm_release" "cert-manager" {
  count = var.install_cert_manager ? 1 : 0

  name      = "cert-manager"
  chart     = "${path.module}/../cert-manager/helm"
  namespace = kubernetes_namespace.infra.metadata[0].name
  wait      = true
  timeout   = 600

  depends_on = [helm_release.service]
}

# cert-manager-config's Issuer is a plain cert-manager selfSigned type (no external PKI, no auth)
# — only needs cert-manager's own CRDs/webhook to exist first, hence depends_on cert-manager
# specifically. wait=true above (not the repo's usual wait=false) is what actually closes the CRD
# race for this one: it forces terraform to block until cert-manager's CRDs+webhook are ready
# before this release ever applies.
resource "helm_release" "cert-manager-config" {
  name      = "cert-manager-config"
  chart     = "${path.module}/../cert-manager-config/helm"
  namespace = kubernetes_namespace.infra.metadata[0].name
  wait      = false
  timeout   = 300

  # Same "namespace" value override as helm_release.service's own — see that block's comment.
  set {
    name  = "namespace"
    value = kubernetes_namespace.infra.metadata[0].name
  }

  depends_on = [helm_release.cert-manager, helm_release.service]
}

# Not in the for_each above — services/apollo/helm/values.supergraph.yaml is still the
# checked-in placeholder (no subgraphs registered in rover.yaml yet), so the router can never
# actually start; wait=false keeps that from stalling every apply.
resource "helm_release" "apollo" {
  name      = "apollo"
  chart     = "${path.module}/../apollo/helm"
  namespace = kubernetes_namespace.infra.metadata[0].name
  wait      = false

  values = [
    file("${path.module}/../apollo/helm/values.supergraph.yaml"),
  ]

  depends_on = [terraform_data.helm_dep_update]
}
