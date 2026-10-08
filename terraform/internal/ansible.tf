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
    for f in fileset("${path.module}/../../helm/ansible/flows", "*") :
    f => file("${path.module}/../../helm/ansible/flows/${f}")
  }
}

# ponytail: the SDLC OpenWebUI pipe (helm/ansible/pipe/sdlc_pipe.py) — mounted
# at /pipe, same pattern as ansible_n8n_flows. Kept out of the helm chart
# package via helm/ansible/.helmignore.
resource "kubernetes_config_map" "ansible_pipe" {
  metadata {
    name      = "ansible-pipe"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
  data = {
    for f in fileset("${path.module}/../../helm/ansible/pipe", "*") :
    f => file("${path.module}/../../helm/ansible/pipe/${f}")
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
    # ponytail: n8n API key playbooks/n8n.yml uses for the mcp-servers-n8n
    # deployment — persisted here instead of minted fresh every run (n8n
    # only ever returns the raw secret once, at creation). Blank on first
    # run: n8n.yml mints one and prints it so you can paste it into .env.
    n8n_mcp_api_key       = var.n8n_mcp_api_key
    # ponytail: SSO-only login (ENABLE_LOGIN_FORM=False) means openwebui.yml
    # can't script a password login like n8n.yml does. Blank on first run —
    # log into OpenWebUI once via the browser (SSO), Settings -> Account ->
    # API Keys -> generate, paste it here.
    openwebui_api_key = var.openwebui_api_key
    litellm_master_key    = var.litellm_master_key
    gitlab_webhook_secret = var.gitlab_webhook_secret
    gitlab_group_id       = var.gitlab_group_id
    # ponytail: role-accounts.yml's shared-fallback Kaneo credential (per-role
    # keys it mints go into omp-role-kaneo-tokens instead, same split as
    # omp_gitlab_token/omp-role-gitlab-tokens).
    kaneo_api_token = var.kaneo_api_token
    # role-accounts.yml signs in as this bootstrap admin (POST
    # /api/auth/sign-in/email) to create per-role Kaneo users + API keys.
    kaneo_admin_email    = var.admin_email
    kaneo_admin_password = var.kaneo_admin_password
    # ponytail: gitlab-webhook.yml also sets these as sdlc-group CI/CD
    # variables so generated projects can push to Harbor without GitLab's
    # own $CI_REGISTRY_* auto-vars (which only exist for its bundled registry).
    harbor_admin_password = var.harbor_admin_password
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

# ponytail: gitlab-webhook.yml runs `rails runner` inside the webservice pod to
# mint a fresh PAT (PATs die with the DB) — needs pod read + exec in `gitlab`.
resource "kubernetes_role" "ansible_gitlab_exec" {
  metadata {
    name      = "ansible-gitlab-exec"
    namespace = "gitlab"
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
  depends_on = [kubernetes_namespace.gitlab]
}

resource "kubernetes_role_binding" "ansible_gitlab_exec" {
  metadata {
    name      = "ansible-gitlab-exec"
    namespace = "gitlab"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_gitlab_exec.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

# argocd-clusters.yml writes one Secret per registered external cluster
# (argocd.argoproj.io/secret-type: cluster convention — ArgoCD reads these
# directly, no argocd CLI/API token needed for registration itself).
resource "kubernetes_role" "ansible_argocd_clusters" {
  metadata {
    name      = "ansible-argocd-clusters"
    namespace = "argocd"
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "patch"]
  }
  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_role_binding" "ansible_argocd_clusters" {
  metadata {
    name      = "ansible-argocd-clusters"
    namespace = "argocd"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_argocd_clusters.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

# ponytail: Kaneo's admin endpoints are gated by a session cookie, not pod
# exec (Better Auth sign-in/email + admin plugin, all normal in-cluster
# HTTP) -- no pods/exec RBAC needed for Kaneo the way Taiga's manage.py
# shell approach needed, so nothing replaces ansible_taiga_exec here.

# ponytail: role-accounts.yml writes the 12 per-role GitLab tokens it mints
# straight into a plain Secret here (not a helm value -- see the playbook's
# own comment), so the ansible-runner SA needs write access to `secrets` in
# `sdlc`, same cross-namespace shape as ansible_gitlab_exec above, just
# secrets instead of pods/exec.
resource "kubernetes_role" "ansible_sdlc_secrets" {
  metadata {
    name      = "ansible-sdlc-secrets"
    namespace = "sdlc"
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "patch", "update"]
  }
  depends_on = [kubernetes_namespace.sdlc]
}

resource "kubernetes_role_binding" "ansible_sdlc_secrets" {
  metadata {
    name      = "ansible-sdlc-secrets"
    namespace = "sdlc"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_sdlc_secrets.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

# ponytail: a Secret's secretKeyRef only resolves within its own namespace —
# n8n's native (non-agent-pod) MR-review flow (F-04) needs tech-lead's own
# GitLab PAT to post approvals/comments as tech-lead instead of n8n's shared
# admin token, but n8n runs in namespace `n8n`, not `sdlc`. role-accounts.yml
# mirrors the same role-token map into this namespace too so n8n's own pod
# env (helm/n8n/values.yaml's main.extraEnv) can reference it locally.
resource "kubernetes_role" "ansible_n8n_secrets" {
  metadata {
    name      = "ansible-n8n-secrets"
    namespace = "n8n"
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "patch", "update"]
  }
  depends_on = [kubernetes_namespace.n8n]
}

resource "kubernetes_role_binding" "ansible_n8n_secrets" {
  metadata {
    name      = "ansible-n8n-secrets"
    namespace = "n8n"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.ansible_n8n_secrets.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "ansible-runner"
    namespace = kubernetes_namespace.ansible.metadata[0].name
  }
}

resource "helm_release" "ansible" {
  name      = "ansible"
  chart     = "${path.module}/../../helm/ansible"
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
      for f in fileset("${path.module}/../../helm/ansible", "**") : filesha1("${path.module}/../../helm/ansible/${f}")
      if !startswith(f, "flows/") && !startswith(f, "pipe/") # both go in via configmaps above, not the chart
    ]))
  }

  depends_on = [
    kubernetes_config_map.ansible_n8n_flows,
    kubernetes_config_map.ansible_pipe,
    kubernetes_secret.ansible_secrets,
  ]
}
