resource "kubernetes_namespace" "ansible" {
  metadata {
    name = "ansible"
  }
}

# ponytail: the n8n SDLC flows + seed.sh — mounted at /flows in the runner,
# seeded by playbooks/n8n.yml. Kept out of the helm chart package via
# helm/ansible/.helmignore (nothing templates them).
resource "kubernetes_config_map" "ansible_n8n_flows" {
  metadata {
    name      = "ansible-n8n-flows"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
  data = {
    for f in fileset("${path.module}/../helm/ansible/flows", "*") :
    f => file("${path.module}/../helm/ansible/flows/${f}")
  }
}

resource "kubernetes_secret" "ansible_secrets" {
  metadata {
    name      = "ansible-secrets"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
  # ponytail: one Secret, envFrom'd into the runner — playbooks read any key via
  # lookup('env', '<key>'). Source of truth is .env (TF_VAR_*). Rotate a token:
  # edit .env, `tofu apply -target=kubernetes_secret.ansible_secrets`, then
  # `scripts/ansible-run.sh mcp-servers`.
  data = {
    n8n_owner_email       = var.admin_email
    n8n_owner_password    = var.n8n_owner_password
    grafana_mcp_token     = var.grafana_mcp_token
    sonarqube_mcp_token   = var.sonarqube_mcp_token
    gitlab_mcp_token      = var.gitlab_mcp_token
    gitlab_mcp_auth_token = var.gitlab_mcp_auth_token
    omp_gitlab_token = var.omp_gitlab_token
    litellm_master_key    = var.litellm_master_key
  }
}

# ponytail: lets the ansible-ns runner SA patch env into the mcp-servers
# Deployments (mcp-servers.yml). Scoped to that one namespace, get+patch only.
resource "kubernetes_role" "ansible_mcp_patch" {
  metadata {
    name      = "ansible-mcp-patch"
    namespace = "mcp-servers"
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "patch"]
  }
  depends_on = [kubernetes_namespace.mcp_servers]
}

resource "kubernetes_role_binding" "ansible_mcp_patch" {
  metadata {
    name      = "ansible-mcp-patch"
    namespace = "mcp-servers"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_mcp_patch.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

# ponytail: same deal for the omp namespace — omp.yml pushes the
# GitLab token into every omp Deployment's env.
resource "kubernetes_role" "ansible_omp_patch" {
  metadata {
    name      = "ansible-omp-patch"
    namespace = "omp"
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "patch"]
  }
  depends_on = [kubernetes_namespace.omp]
}

resource "kubernetes_role_binding" "ansible_omp_patch" {
  metadata {
    name      = "ansible-omp-patch"
    namespace = "omp"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_omp_patch.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

# ponytail: mattermost.yml runs `mmctl --local` inside the mattermost pod via
# kubernetes.core.k8s_exec — needs pod read + exec in that one namespace.
resource "kubernetes_role" "ansible_mattermost_exec" {
  metadata {
    name      = "ansible-mattermost-exec"
    namespace = "mattermost"
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["get", "create"]
  }
  depends_on = [kubernetes_namespace.mattermost]
}

resource "kubernetes_role_binding" "ansible_mattermost_exec" {
  metadata {
    name      = "ansible-mattermost-exec"
    namespace = "mattermost"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_mattermost_exec.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

resource "helm_release" "ansible" {
  name      = "ansible"
  chart     = "${path.module}/../helm/ansible"
  namespace = kubernetes_namespace.ansible.metadata[0].name
  # ponytail: nothing runs on apply — the CronJob is suspended. Trigger playbooks
  # with scripts/ansible-run.sh.
  wait = false

  # ponytail: the helm provider doesn't hash local chart files, so edits to
  # playbooks/values wouldn't redeploy on their own. Fold a dir hash into an
  # unused value so any change forces an upgrade (mirrors omp.tf's trigger).
  set {
    name = "chartHash"
    value = sha1(join(",", [
      for f in fileset("${path.module}/../helm/ansible", "**") : filesha1("${path.module}/../helm/ansible/${f}")
      if !startswith(f, "flows/") # flows go in via the configmap above, not the chart
    ]))
  }

  depends_on = [
    kubernetes_config_map.ansible_n8n_flows,
    kubernetes_secret.ansible_secrets,
  ]
}
