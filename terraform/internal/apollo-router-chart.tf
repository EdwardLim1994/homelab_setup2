# ponytail: packages helm/apollo-router as an OCI artifact and pushes it to
# Harbor — the chart NEVER lives in any generated project's own repo (see
# devops-engineer/SKILL.md's "Apollo Router Provisioning"); every project's
# ArgoCD Application references it by OCI ref + version instead, same as any
# other externally-hosted Helm chart. Uses Harbor's default "library"
# project (already exists, no separate provisioning — every image push in
# this repo already targets library/... the same way, see harbor.tf).
#
# local-exec runs on the HOST, which can't resolve harbor.harbor.svc.cluster.local
# — port-forward for the duration of the push instead of standing up a new
# NodePort bridge just for this (same class of problem harbor_oidc_config
# solves differently, via a one-shot in-cluster curl pod; port-forward is
# simpler here since a file needs to travel, not just a request).
resource "null_resource" "apollo_router_chart_push" {
  triggers = {
    chart_hash = sha1(join(",", [
      for f in fileset("${path.module}/../../helm/apollo-router", "**") :
      filesha1("${path.module}/../../helm/apollo-router/${f}")
    ]))
  }

  provisioner "local-exec" {
    interpreter = [local.bash_bin, "-c"]
    command     = <<-EOT
      set -e
      kubectl --context ${var.kube_context} port-forward -n harbor svc/harbor 18080:80 >/dev/null 2>&1 &
      pf_pid=$!
      trap 'kill $pf_pid 2>/dev/null || true' EXIT
      sleep 3

      helm package "${path.module}/../../helm/apollo-router" -d /tmp
      version=$(grep '^version:' "${path.module}/../../helm/apollo-router/Chart.yaml" | awk '{print $2}')
      helm registry login localhost:18080 -u admin -p "${var.harbor_admin_password}" --plain-http
      helm push "/tmp/apollo-router-$${version}.tgz" oci://localhost:18080/library/charts --plain-http
    EOT
  }

  depends_on = [helm_release.harbor]
}
