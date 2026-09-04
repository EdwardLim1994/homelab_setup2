resource "kubernetes_namespace" "omp" {
  metadata {
    name = "omp"
  }
}

# ponytail: omp is the only app with a locally-built image. Terraform
# can't build, so shell out to docker build + push into the k3d registry
# (the same one Tilt uses). Triggers rebuild only when the Dockerfile,
# chart values, or baked config actually change.
resource "null_resource" "omp_image" {
  triggers = {
    dockerfile = filesha1("${path.module}/../helm/omp/Dockerfile")
    values     = filesha1("${path.module}/../helm/omp/values.yaml")
    # ponytail: roles/ (role SKILL.md + baked sub-skill packs) is COPY'd into
    # the image — hash the whole tree so adding/editing a skill rebuilds it.
    roles = sha1(join(",", [
      for f in fileset("${path.module}/../helm/omp/roles", "**") :
      filesha1("${path.module}/../helm/omp/roles/${f}")
    ]))
  }

  provisioner "local-exec" {
    # ponytail: run from the chart dir with "." as context — a bare "." has
    # no drive-letter path for git-bash to mangle into "path not found".
    working_dir = abspath("${path.module}/../helm/omp")
    command     = "docker build -t localhost:5111/omp-box:dev . && docker push localhost:5111/omp-box:dev"
  }
}

# ponytail: mirrors helm/omp/Tiltfile — Claude Code OAuth token for the
# `claude` CLI in omp pods. Chart mounts it via claudeAuth.secretName with
# optional:true, so a blank token just leaves `claude` unauthenticated.
resource "kubernetes_secret" "omp_claude_auth" {
  metadata {
    name      = "omp-claude-auth"
    namespace = kubernetes_namespace.omp.metadata[0].name
  }
  data = {
    CLAUDE_CODE_OAUTH_TOKEN = var.claude_code_token
  }
  depends_on = [kubernetes_namespace.omp]
}

resource "helm_release" "omp" {
  name              = "omp"
  chart             = "${path.module}/../helm/omp"
  namespace         = kubernetes_namespace.omp.metadata[0].name
  dependency_update = true
  # ponytail: chart defaults to replicas=0 (wake-on-demand). Nothing to wait
  # for on apply — wake it with scripts/omp-shell.sh.
  wait = false

  values = [file("${path.module}/../helm/omp/values.yaml")]

  # in-cluster registry name; host push target is localhost:5111 (see null_resource above).
  set {
    name  = "image"
    value = "k3d-registry:5111/omp-box:dev"
  }

  # ponytail: k3d-internal (terraform's target) has no /var/run/docker.sock
  # node mount — that was only added to the k3d-internal-dev cluster via
  # create-cluster.sh. Adding it here needs a destructive cluster recreate,
  # so leave it off; the agent just can't run `docker` inside the pod.
  set {
    name  = "dockerSocket.enabled"
    value = "false"
  }

  depends_on = [kubernetes_namespace.omp, null_resource.omp_image, kubernetes_secret.omp_claude_auth]
}
