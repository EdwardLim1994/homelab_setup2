resource "kubernetes_namespace" "sdlc" {
  metadata {
    name = "sdlc"
  }
}

# ponytail: omp-agent's Job image is the same image helm/omp's Dockerfile
# builds (omp + opencode + claude CLIs, every role's skill dir baked in) —
# reused rather than duplicated. Mirrors the build step that used to live in
# the now-deleted terraform/omp.tf.
resource "null_resource" "omp_agent_image" {
  triggers = {
    dockerfile = filesha1("${path.module}/../helm/omp/Dockerfile")
    roles = sha1(join(",", [
      for f in fileset("${path.module}/../helm/omp/roles", "**") :
      filesha1("${path.module}/../helm/omp/roles/${f}")
    ]))
  }

  provisioner "local-exec" {
    working_dir = abspath("${path.module}/../helm/omp")
    command     = "docker build -t localhost:5111/omp-box:dev . && docker push localhost:5111/omp-box:dev"
  }
}

resource "helm_release" "omp_agent" {
  name              = "omp-agent"
  chart             = "${path.module}/../helm/omp-agent"
  namespace         = kubernetes_namespace.sdlc.metadata[0].name
  dependency_update = true

  values = [file("${path.module}/../helm/omp-agent/values.yaml")]

  set {
    name  = "namespace"
    value = kubernetes_namespace.sdlc.metadata[0].name
  }

  # reuse existing tokens — see terraform/variables.tf
  set_sensitive {
    name  = "secrets.gitlabToken"
    value = var.omp_gitlab_token
  }

  set_sensitive {
    name  = "secrets.claudeCodeToken"
    value = var.claude_code_token
  }

  set_sensitive {
    name  = "secrets.gitlabRepoUrl"
    value = var.omp_gitlab_repo_url
  }

  depends_on = [kubernetes_namespace.sdlc, null_resource.omp_agent_image]
}
