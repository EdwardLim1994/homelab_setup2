resource "kubernetes_namespace" "opencode" {
  metadata {
    name = "opencode"
  }
}

# ponytail: opencode is the only app with a locally-built image. Terraform
# can't build, so shell out to docker build + push into the k3d registry
# (the same one Tilt uses). Triggers rebuild only when the Dockerfile,
# chart values, or baked config actually change.
resource "null_resource" "opencode_image" {
  triggers = {
    dockerfile = filesha1("${path.module}/../helm/opencode/Dockerfile")
    values     = filesha1("${path.module}/../helm/opencode/values.yaml")
  }

  provisioner "local-exec" {
    # ponytail: run from the chart dir with "." as context — a bare "." has
    # no drive-letter path for git-bash to mangle into "path not found".
    working_dir = abspath("${path.module}/../helm/opencode")
    command     = "docker build -t localhost:5111/opencode-box:dev . && docker push localhost:5111/opencode-box:dev"
  }
}

resource "helm_release" "opencode" {
  name              = "opencode"
  chart             = "${path.module}/../helm/opencode"
  namespace         = kubernetes_namespace.opencode.metadata[0].name
  dependency_update = true
  # ponytail: chart defaults to replicas=0 (wake-on-demand). Nothing to wait
  # for on apply — wake it with scripts/opencode-shell.sh.
  wait = false

  values = [file("${path.module}/../helm/opencode/values.yaml")]

  # in-cluster registry name; host push target is localhost:5111 (see null_resource above).
  set {
    name  = "image"
    value = "k3d-registry:5111/opencode-box:dev"
  }

  # ponytail: k3d-internal (terraform's target) has no /var/run/docker.sock
  # node mount — that was only added to the k3d-internal-dev cluster via
  # create-cluster.sh. Adding it here needs a destructive cluster recreate,
  # so leave it off; the agent just can't run `docker` inside the pod.
  set {
    name  = "dockerSocket.enabled"
    value = "false"
  }

  depends_on = [kubernetes_namespace.opencode, null_resource.opencode_image]
}
