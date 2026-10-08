# omp-agent

Generic omp agent Job template + per-role skill ConfigMaps for the SDLC
pipeline. n8n creates one Kubernetes Job per role per story, dynamically,
via the Kubernetes API — this chart does **not** deploy Jobs itself.

What Helm/Terraform *does* own: the `sdlc` namespace's role ConfigMaps, the
`omp-agent` ServiceAccount/Role/RoleBinding the Job pods run as, and the
`omp-agent-secrets` Secret they read from. `job-reference.yaml` (deliberately outside `templates/`, so Helm never
installs it) is a reference manifest only — copy its shape into n8n's HTTP
Request node.

## Role → model

`OMP_MODEL` is **not** an n8n token — it lives in the role's own ConfigMap
(`templates/configmaps.yaml`) and the Job reads it via `configMapKeyRef`, so
this table is the single source of truth (n8n only picks the role):

| Role | ConfigMap name | OMP_MODEL |
|---|---|---|
| tech-lead | `omp-skill-tech-lead` | `ollama/qwen3.8:27b` |
| architect | `omp-skill-architect` | `ollama/qwen3.8:27b` |
| data-engineer | `omp-skill-data-engineer` | `ollama/qwen3.8:27b` |
| devops-engineer | `omp-skill-devops-engineer` | `ollama/qwen3.8:27b` |
| release-manager | `omp-skill-release-manager` | `ollama/qwen3.8:27b` |
| backend-developer | `omp-skill-backend-developer` | `ollama/qwen3:1.7b` |
| frontend-developer | `omp-skill-frontend-developer` | `ollama/qwen3:1.7b` |
| qa-engineer | `omp-skill-qa-engineer` | `ollama/qwen3:1.7b` |
| security-engineer | `omp-skill-security-engineer` | `ollama/qwen3:1.7b` |
| product-manager | `omp-skill-product-manager` | `ollama/qwen3:1.7b` |
| ui-ux-designer | `omp-skill-ui-ux-designer` | `ollama/qwen3:1.7b` |

Must stay a subset of `helm/litellm/values.yaml`'s `ollamaModels` (what's
actually pulled on the host — check with `ollama list`); LiteLLM only
mirrors that list for other callers, it doesn't route the omp pod's own
model choice. `qwen3-coder-next` (80B) is pulled but excluded from both —
OOMs on this host.

ConfigMap `SKILL.md` content is currently a placeholder (`Step 2` of the
build spec) — `.agents/skills/<role>/SKILL.md` / `sdlc-agent-skills.zip`
weren't present in either repo at build time. Swap
`templates/configmaps.yaml`'s inline content for the real SKILL.md once
available.

## Substitution map (n8n → job-reference.yaml)

| Token | Source in n8n | Example |
|---|---|---|
| `{{ role }}` | roles.json field `role` | `backend-developer` |
| `{{ story }}` | roles.json field `story` | `GL-42` |
| `{{ task_branch }}` | roles.json field `pods[n].tasks[0]` branch | `task/GL-101` |
| `{{ task_ids }}` | roles.json field `pods[n].tasks` joined | `GL-101,GL-102` |
| `{{ timestamp }}` | n8n `{{ $now.toFormat('yyyyMMddHHmmss') }}` | `20260911103045` |
| `{{ callback_url }}` | n8n webhook URL for this execution | `https://n8n.ts.net/webhook/omp-cb` |
| `{{ omp_image }}` | hardcoded or from n8n env var | `registry.homelab/omp:latest` |

## n8n HTTP Request node config

```
Method:  POST
URL:     https://kubernetes.default.svc/apis/batch/v1/namespaces/sdlc/jobs
Headers: Authorization: Bearer <n8n serviceaccount token>
         Content-Type: application/json
Body:    <job.yaml rendered as JSON with tokens substituted>
```

n8n's ServiceAccount (the subchart's default, release name `n8n`) is bound
to a namespace-scoped Role in `sdlc` via `helm/n8n/templates/omp-agent-rbac.yaml`
(`jobs: create, get`) — separate from `omp-agent`'s own Role, which is what
the Job **pods** run as (`templates/role.yaml`: jobs create/get/list/watch/delete,
pods get/list/watch, pods/log get/list, configmaps get/list).

## Callback contract

Each omp pod's final step posts to `N8N_CALLBACK_URL`:

```json
{
  "role": "backend-developer",
  "story": "GL-42",
  "pod_id": "omp-backend-developer-GL42-20260911103045",
  "tasks": ["GL-101", "GL-102"],
  "status": "success",
  "mr_urls": ["https://gitlab.../merge_requests/55"]
}
```

n8n waits for N callbacks (N = total pods created for the story) before
posting the consolidated result to Mattermost.

## Secrets

`omp-agent-secrets` (plain K8s Secret — no ExternalSecret operator in this
cluster) carries `gitlab_token` (reuses `TF_VAR_omp_gitlab_token`),
`claude_code_token` (reuses `TF_VAR_claude_code_token`), and
`gitlab_repo_url` (new: `TF_VAR_omp_gitlab_repo_url`, set in `.env`),
`kaneo_token` (`TF_VAR_kaneo_api_token`, bootstrap-once via the
browser like `openwebui_api_key`), and `kaneo_url` (the in-cluster service
address, not a `.env` value — pods can't reach the tailnet VIP).

## Not done here

- No Deployment/StatefulSet — Jobs only, scale-to-zero.
- n8n's actual "create Job" HTTP node isn't built — this is the contract
  doc for whoever wires that flow.
