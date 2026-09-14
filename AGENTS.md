# AGENTS.md

Read by omp/opencode agent pods and by Claude Code when acting on the
autonomous SDLC this repo runs. For the repo's own layout/conventions see
`AGENT.md`; this file is scoped to the SDLC itself.

## Project identity

- This repo (`homelab_setup2`) is the **infra** that runs the SDLC — the
  k3d cluster, n8n flows, omp chart, and role skills. It is not the target
  application the SDLC develops. Agent pods operate on a separate
  application repo cloned into `$REPO_DIR` (the `--project` flag on every
  `omp`/`opencode` invocation below) — that repo's own stack, generated
  code, and build tooling are out of scope here.
- Stack (this repo): Authentik SSO, GitLab, MinIO, n8n, SonarQube,
  Nextcloud, ArgoCD, an LGTM observability stack, LiteLLM, OpenWebUI, MCP
  servers, and the `omp` agent stack.

## SDLC command reference

Triggered by chatting with the **SDLC** model in OpenWebUI (`sdlc_pipe.py`,
installed by `playbooks/openwebui.yml`) — see `README.md`'s Autonomous SDLC
section for the full table. Reproduced here for the same reference:

| Command | Phase | What it triggers |
|---|---|---|
| `/plan_release` | 0 — Planning | Multi-agent planning: Arch+DE gate A → QA+Sec+UX gate B → PM PRD gate C |
| `/kickoff` | 0 — Kickoff | 3 parallel tracks: TL branches+pseudocode (omp) · PM GitLab artifacts (opencode) · DevOps infra+webhook (omp) |
| `/develop` | 2 — Development | Gates A (DevOps) → B (Data Engineer) → C (TL pseudocode) → developer pods fan out |
| `/uat` | 3 — UAT | Milestone safeguard → manual CI → UAT deploy → QA → Security → PO stages |
| `/release_staging` | 4 — Staging | UAT safeguard → RM release-plan ticket + promote/ branch → promotion CI |
| `/release_production` | 5 — Production | rm:go safeguard → promote→main MR → Edward reviews + merges |
| `/rollback` | 5 — Production | ArgoCD rollback + incident ticket + RM monitoring |
| `/rollback_story` | 5 — Production | Dependency check → revert MR → TL reviews → Edward merges → story Deferred → /uat re-triggered |
| `/retro` | 6 — Retrospective | 4 pods compile in parallel (TL+QA+Sec+RM) → PM synthesises 11-section report |
| `/projects` | Any | Instant DAG state query — no agent pod spawned |
| `/escalate` | Any | Pause DAG, post alert to OpenWebUI immediately |

## n8n flow map

28 flows, `helm/ansible/flows/F-*.json`, seeded by `helm/ansible/flows/seed.sh`.
Webhook paths below are each flow's actual `Webhook Trigger` `path` field.

### Slash-command flows (11)

- **F-01** `/plan_release` → `webhook/plan-release` — multi-agent planning gate
- **F-02** `/kickoff` → `webhook/kickoff` — 3 parallel tracks: TL, PM, DevOps
- **F-03** `/develop` → `webhook/develop` — gates A→B→C then developer pods fan out
- **F-10** `/uat` → `webhook/uat` — milestone safeguard, UAT deploy, QA→Security→PO
- **F-14** `/release_staging` → `webhook/release-staging` — RM release-plan + promote/ branch
- **F-17** `/release_production` → `webhook/release-production` — rm:go safeguard, create promote→main MR
- **F-21** `/rollback` → `webhook/rollback` — ArgoCD rollback + incident ticket
- **F-22** `/rollback_story` → `webhook/rollback-story` — dependency check + revert MR
- **F-24** `/retro` → `webhook/retro` — 4 pods parallel, PM synthesises report
- **F-25** `/escalate` → `webhook/escalate` — pause DAG + alert
- **F-26** `/projects` → `webhook/projects` — DAG state query, no pod spawned

### GitLab/CI event flows (17)

- **F-00** GitLab Event Router — single endpoint `webhook/gitlab-events`, routes by event + branch prefix (registered per-project by `gitlab-webhook.yml`, GitLab CE has no group hooks)
- **F-04** Task MR opened (`webhook/gitlab-task-mr-opened`) — TL review parallel with CI, retry counter max 3 → `/escalate`
- **F-05** Task MR merged (`webhook/gitlab-task-mr-merged`) — update DAG, trigger DoD when all tasks done
- **F-06** DoD check (`webhook/dod-check`) — TL slow model, pass → story MR, fail → feedback + re-trigger F-04
- **F-07** Story MR open (`webhook/story-mr-open`) — TL opens MR (opencode+glab), QA tests, notify Edward
- **F-08** Story MR merged (`webhook/gitlab-story-mr-merged`) — close tickets, sleep QA, check all stories done
- **F-09** CI pipeline / version built (`webhook/gitlab-pipeline`) — update DAG state (ArgoCD Image Updater handles SIT)
- **F-11** UAT QA stage (`webhook/uat-qa`) — QA sign-off → `qa:uat-approved` label
- **F-12** UAT Security stage (`webhook/uat-security`) — Security sign-off → `security:cleared` label
- **F-13** UAT PO stage (`webhook/uat-po`) — PO sign-off → `po:uat-approved` label, notify Edward
- **F-15** Staging deployed (`webhook/staging-deployed`) — QA k6 + Security ZAP parallel → RM go/no-go
- **F-16** Go/no-go (`webhook/go-nogo`) — GO: `rm:go` label + notify; NO-GO: 3-option report + notify Edward
- **F-18** Release MR merged (`webhook/gitlab-release-mr-merged`) — notify, hand off to CI
- **F-19** Production deployed (`webhook/production-deployed`) — smoke tests → RM monitoring or escalate
- **F-20** Monitoring window (`webhook/monitoring-window`) — incident: escalate; clean: confirm release + PM comms + sleep staging
- **F-23** Revert MR merged (`webhook/gitlab-revert-merged`) — story Deferred, re-trigger `/uat`
- **F-27** Cluster lifecycle (`webhook/cluster-lifecycle`) — wake/sleep QA/UAT/staging clusters

ponytail: `helm/ansible/flows/` also holds a handful of alternate-name
duplicates (`F-00-gitlab-router.json`, `F-07-flow.json`, `F-08-flow.json`,
`F-09-flow.json`, `F-11/12/13-*-complete.json`, `F-23-revert-mr-merged.json`)
and a stale `F-28-chat.json` (Mattermost chat — Mattermost is removed, see
`AGENT.md`). Not seeded; the 28 files listed above are the canonical set.
Worth a cleanup pass, not done here.

## Agent runtime rules

Confirmed from the actual flow commands (`helm/ansible/flows/F-*.json`):

**omp** (`omp --role <role> --model <tier> --project $REPO_DIR --prompt '...' --non-interactive`) — every code-editing / analysis role:
- `slow` — Tech Lead (pseudocode authoring, MR review, DoD check)
- `default` — DevOps Engineer, Data Engineer
- `smol` — Backend Developer, Frontend Developer, QA Engineer, Security Engineer
- Also seen: Architect, UI/UX Designer (`--role architect`, `--role ui-ux-designer`, both `--model slow`/`smol` respectively in F-01)

**opencode** (`opencode --role <role> --model <tier> --prompt '...' --non-interactive`, no `--project` — GitLab-facing ops only, `glab` CLI):
- `haiku` — PM (`--role pm`): GitLab issue/milestone/epic creation, release comms, retro synthesis
- `sonnet` — Tech Lead's glab-only steps (`--role tech-lead`: opening/reverting story MRs), Release Manager's release-plan ticket (`--role release-manager`)

ponytail: role names as literally invoked (`architect`, `pm`, `ui-ux-designer`)
don't all match `helm/omp/values.yaml`'s role list (`solution-architect`,
`product-owner`/`project-manager`, `uiux-designer`) — pre-existing naming
drift between the flow JSON and the chart, not resolved here.

Role skill files: `helm/omp/roles/<role>/SKILL.md`, baked into the omp image
and linked into both `~/.omp/agent/skills/<role>` and
`~/.claude/skills/<role>` (`helm/omp/Dockerfile`).

## Hard rules for all agent pods

- Data Engineer's `api/GL-{N}` branch merges first and blocks all other task branches (see README's Branch hierarchy)
- Retry limit for task MR review failures: 3 attempts (F-04), then `/escalate`
- F-00 is the single GitLab webhook entrypoint — don't add a second per-flow GitLab webhook

## Human approval gates

Edward is the sole human in the loop. The 4 gates are:

1. Reviews openspec + pseudocode before `/develop`
2. Merges story MRs
3. Merges release MR to main
4. Makes go/no-go decisions on NO-GO outcomes and production incidents

Do not wait for human input at any other point — everything outside these
gates is autonomous.
