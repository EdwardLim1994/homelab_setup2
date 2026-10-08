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

### Which GitLab group/project — `sdlc/hr-portal` is a dry-run fixture, not a default to build real projects against

`/plan_release <version> [group] [project]` creates/uses whatever
group/project you name (falls back to `sdlc`/`hr-portal` if you don't name
one — that pair exists only to verify the pipeline works, never treat it as
"the" project). Every OTHER flow (`/kickoff`, `/develop`, `/uat`, …) does
**not** read the group/project from the chat message at all — they read the
static n8n Variables `GITLAB_PROJECT_PATH`, `GITLAB_PROJECT_ID`,
`ARGOCD_PROJECT`, `DEPLOY_NAMESPACE` (same "one project in flight" pattern
`RELEASE_VERSION` already uses). So starting a real project is two steps,
not one:

1. `/plan_release v1.0.0 my-team my-app` — creates the group+project.
2. Update those 4 Variables to match (n8n Settings → Variables, or
   `.env` → `scripts/*/gen-tfvars.*` → `tofu apply` → reseed) **before**
   running `/kickoff` — otherwise every later flow keeps operating against
   whatever those Variables currently say, silently ignoring step 1.

`F-01-plan-release.json`'s `PM Project Input` step reports a loud warning
when the created group/project differs from `sdlc/hr-portal`, precisely so
step 2 isn't forgotten.

## Generated repo structure — nx monorepo, one fixed layout

Every generated application repo (`$REPO_DIR`) is a single nx monorepo.
Solution Architect scaffolds this layout at first `/plan_release`/`/kickoff`
(see solution-architect/SKILL.md's Stack Selection) — every other role reads
and writes within it, never outside it:

```
apps/backend/{service name}/    one nx app per backend service
apps/frontend/{web or mobile app name}/   one nx app per frontend app
packages/                       shared libs (published to this GitLab
                                 instance's npm registry — see
                                 solution-architect/SKILL.md's CI wiring)
schemas/                        Kafka/GraphQL/proto schemas — see
                                 data-engineer/SKILL.md, pushed to Apicurio
tests/e2e/                      cross-story / full-journey Playwright specs
                                 (QA's UAT stage + production smoke tests)
tests/integration/              single-story Playwright specs against real
                                 SIT deps (QA's story-level testing)
```

Rules every role that touches the repo must follow:
- **Never a bare `apps/{name}/`** — always nested under `apps/backend/` or
  `apps/frontend/`. A service's nx project name is just `{name}` (nx doesn't
  care about nesting depth), but its root path always includes the
  backend/frontend segment — resolve it via `nx show project {name} --json
  | jq -r .root` rather than assuming/reconstructing the path, so a
  script/pseudocode reference never goes stale if nesting conventions shift.
- **`package.json` is per-app, never root** — every "bump package.json
  version" instruction means `apps/{backend|frontend}/{name}/package.json`,
  not a repo-root one (this repo has no meaningful root version).
- **One Dockerfile per app**, alongside its `package.json` — the CI `build`
  stage builds+pushes one image per *affected* app (via `nx affected`), not
  one repo-wide image. Image tag path is `$CI_REGISTRY_IMAGE/{name}` — the nx
  project name, no `apps/backend/`/`apps/frontend/` prefix baked into the
  registry path (matches devops-engineer/SKILL.md's `promote.sh`, which
  already reads/writes per-service `env/{env}/{name}/values.yaml`).
- **Unit tests stay co-located** inside their own app (`apps/{backend|frontend}/{name}/src/**/*.test.ts`,
  run via `nx test {name}`) — that's standard nx convention, distinct from
  `tests/e2e`/`tests/integration` above.
- **CI (`lint`/`test`/`typecheck`) always runs `nx affected`, never
  repo-wide** — same rule backend-developer/frontend-developer already
  follow for their own local pre-MR checks (devops-engineer/SKILL.md's
  `.gitlab-ci.yml` template mirrors this, not a separate/looser rule for CI).

## SDLC command reference

Triggered by chatting with the **SDLC** model in OpenWebUI (`sdlc_pipe.py`,
installed by `playbooks/openwebui.yml`) — see `README.md`'s Autonomous SDLC
section for the full table. Reproduced here for the same reference:

| Command | Phase | What it triggers |
|---|---|---|
| `/plan_release` | 0 — Planning | Multi-agent planning: Arch+DE gate A → QA+Sec+UX gate B → PM PRD gate C |
| `/kickoff` | 0 — Kickoff | 3 parallel tracks: TL branches+pseudocode (omp) · PM Kaneo artifacts (omp) · DevOps infra+webhook (omp) |
| `/develop` | 2 — Development | Gates A (DevOps) → B (Data Engineer) → C (TL pseudocode) → developer pods fan out |
| `/uat` | 3 — UAT | Milestone safeguard → manual CI → UAT deploy → QA → Security → PO stages |
| `/release_staging` | 4 — Staging | UAT safeguard → RM release-plan ticket + promote/ branch → promotion CI |
| `/release_production` | 5 — Production | RM Go status safeguard → promote→main MR → Edward reviews + merges |
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
- **F-17** `/release_production` → `webhook/release-production` — RM Go status safeguard, create promote→main MR
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
- **F-11** UAT QA stage (`webhook/uat-qa`) — QA sign-off → `QA UAT Approved` status
- **F-12** UAT Security stage (`webhook/uat-security`) — Security sign-off → `Security Cleared` status
- **F-13** UAT PO stage (`webhook/uat-po`) — PO sign-off → `PO UAT Approved` status, notify Edward
- **F-15** Staging deployed (`webhook/staging-deployed`) — QA k6 + Security ZAP parallel → RM go/no-go
- **F-16** Go/no-go (`webhook/go-nogo`) — GO: `RM Go` status + notify; NO-GO: 3-option report + notify Edward
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
- `haiku` — PM (`--role pm`): Kaneo epic/story creation, release comms, retro synthesis
- `sonnet` — Tech Lead's glab-only steps (`--role tech-lead`: opening/reverting story MRs), Release Manager's release-plan ticket (`--role release-manager`)

ponytail: role names as literally invoked (`architect`, `pm`, `ui-ux-designer`)
don't all match `helm/omp/values.yaml`'s role list (`solution-architect`,
`product-owner`/`project-manager`, `uiux-designer`) — pre-existing naming
drift between the flow JSON and the chart, not resolved here.

Role skill files: `helm/omp/roles/<role>/SKILL.md`, baked into the omp image
and linked into both `~/.omp/agent/skills/<role>` and
`~/.claude/skills/<role>` (`helm/omp/Dockerfile`).

## Ticket & MR Conventions

Canonical reference for every role's SKILL.md — don't duplicate this, link
to it.

Tickets live in **Kaneo** — GitLab hosts source control, CI, **and wiki**
again (Kaneo has no wiki module at all, unlike Taiga which this replaces —
see "GitLab compliance history" below for why wiki moved back instead of
staying orphaned). `$KANEO_URL`/`$KANEO_TOKEN`/`$KANEO_PROJECT_ID` are n8n
env vars (`helm/n8n/values.yaml` + `terraform/internal/n8n.tf`), same role
every `$env.GITLAB_*` var already plays. Every call is plain REST, bearer
auth:

```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/..."
```

### Ticket type

Unlike Taiga's four separate resources (epic/userstory/task/issue), Kaneo
has **one ticket resource — `task`** — in a flat workspace → project →
task hierarchy. Every kind of work item below is a Kaneo task,
distinguished by a `[role] ...` title prefix (never a separate field) and,
where hierarchy matters, a label. **No epic ticket is created** — GitLab
CE has no Epics either, so a GitLab milestone plus a `v{X}.{Y}.{Z}` label
on every ticket below is the only release-wide grouping (see "Release
grouping" below); don't invent a stand-in epic/initiative ticket, it has no
parent to attach to and ends up as dead weight with nothing but a title:

| Ticket | Kaneo resource | Parent link | Created by |
|---|---|---|---|
| Story | `task`, labelled `story` | none (top-level, tagged with the release label) | PM, at `/kickoff` |
| Task | `task` | `task-relation`, `relationType: "subtask"`, source=task target=story | Tech Lead, one per role×feature (backend/frontend/api), at `/kickoff` |
| QA | `task` | `task-relation`, `relationType: "subtask"`, source=QA-task target=story | QA Engineer, one per story, at `/kickoff` |
| Security | `task` | `task-relation`, `relationType: "subtask"`, source=task target=story | Security Engineer, one per story, at `/kickoff` |
| DevOps | `task` | `task-relation`, `relationType: "subtask"`, source=task target=story | DevOps Engineer, one per story, at `/kickoff` |
| Release | `task` | none | Release Manager, the instant UAT PO sign-off lands |
| Bugfix | `task`, labelled `bugfix` | `task-relation`, `relationType: "subtask"`, source=bug target=story | Whoever finds it (QA/Security), not at kickoff |

Every create needs `project: $KANEO_PROJECT_ID`. Parent/child nesting uses
Kaneo's real `task-relation` resource (confirmed: `POST /api/task-relation`
body `{sourceTaskId, targetTaskId, relationType}`, `relationType` one of
`subtask`/`blocks`/`related`; `GET /api/task-relation/{taskId}` lists a
task's relations both directions) — the child is always `sourceTaskId`,
the parent `targetTaskId`:

```bash
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X POST "$KANEO_URL/api/task-relation" \
  -H "Content-Type: application/json" \
  -d "{\"sourceTaskId\": \"<child-id>\", \"targetTaskId\": \"<parent-id>\", \"relationType\": \"subtask\"}"
```

### Release grouping — a GitLab milestone + a Kaneo label, no epic

GitLab CE has no Epics and Kaneo has no epic resource — don't create a
stand-in epic/initiative ticket for either (see "Ticket type" above for
why that's a dead end: it has no parent to attach to, nothing but a
title). Release-wide grouping is two things instead, both created once at
`/kickoff`: a GitLab milestone, and Kaneo's confirmed workspace-level
**label** primitive (create once, reuse across tasks) — every ticket
shipping in a release carries a `v{X}.{Y}.{Z}` label, e.g. F-26's dashboard
query filters `GET /api/task/tasks/$KANEO_PROJECT_ID` client-side by that
label instead of a server-side version filter (the list endpoint returns
each task's `labels` inline — confirmed — so this read works as written).

**Labels do not exist by default and task creation has no `labels` field
at all** (confirmed: `POST /task/{projectId}` body has no labels/labelIds
param) — a label is its own resource, created on the fly the first time
it's needed, then attached. Resolve-or-create, never blind-create (a
second `POST` with the same name is not confirmed to dedupe):

```bash
# $KANEO_WORKSPACE_ID -- threaded from F-02's "Ensure Kaneo Project" step
# the same way $KANEO_PROJECT_ID is (see F-31's env block).
ensure_label() {
  local name="$1" task_id="$2"
  local lid=$(curl -sH "Authorization: Bearer $KANEO_TOKEN" \
    "$KANEO_URL/api/label/workspace/$KANEO_WORKSPACE_ID" \
    | jq -r --arg n "$name" '.[] | select(.name==$n) | .id')
  if [ -z "$lid" ]; then
    # brand new label -- taskId in the create body attaches it in the same call
    curl -sH "Authorization: Bearer $KANEO_TOKEN" -X POST "$KANEO_URL/api/label" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$name\", \"color\": \"#888888\", \"workspaceId\": \"$KANEO_WORKSPACE_ID\", \"taskId\": \"$task_id\"}" >/dev/null
  else
    # label already exists -- separate attach call
    curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PUT "$KANEO_URL/api/label/$lid/task" \
      -H "Content-Type: application/json" -d "{\"taskId\": \"$task_id\"}" >/dev/null
  fi
}
ensure_label "v{X}.{Y}.{Z}" "$task_id"
ensure_label "qa" "$task_id"   # role/type label, same resolve-or-create
```
<!-- verify this members/create/attach path trio against the deployed Kaneo version -->

### Ticket ↔ branch linkage

Branch names still embed a ticket ref directly — `us/GL-{story-id}`,
`task/GL-{task-id}` — never a title slug, so any pod can parse the id
straight out of its own branch name (`$CI_COMMIT_REF_NAME`) with no lookup.
The `GL-` prefix is kept branch-naming vocabulary only (every SKILL.md
already assumes it) — `{N}` is the Kaneo task's id, not a GitLab issue IID.
Whoever creates the branch (Tech Lead, at kickoff) appends the branch link
to the ticket's own **description** immediately after creation — not a
comment, which scrolls away in the activity feed; the branch link belongs
with the ticket's permanent content. Kaneo has no confirmed optimistic-locking
field on task updates (unlike Taiga's `version`), but a PATCH still
*replaces* `description` wholesale — GET the current description first and
append, don't clobber it:

```bash
desc=$(curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/task/{id}" | jq -r '.description')
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PATCH "$KANEO_URL/api/task/{id}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg desc "$desc" --arg branch "{branch-name}" \
        '{description: ($desc + "\n\n**Branch:** " + $branch)}')"
```

### Ticket status

Every ticket moves through Kaneo's native task status/column field — a
single status vocabulary per project (not Taiga's three parallel
per-ticket-type endpoints, since there's only one ticket resource now).
Resolve the column id by name every time, never hardcode one:

```bash
st_id=$(curl -sH "Authorization: Bearer $KANEO_TOKEN" "$KANEO_URL/api/project/$KANEO_PROJECT_ID/columns" | jq -r '.[] | select(.name=="In progress") | .id')
curl -sH "Authorization: Bearer $KANEO_TOKEN" -X PATCH "$KANEO_URL/api/task/{id}" \
  -H "Content-Type: application/json" \
  -d "{\"statusId\": \"$st_id\"}"
```

Typical path: `Pending` (set at creation) → `In progress` (set by the pod
when it starts work — backend/frontend-developer's Step 1, QA's
story-level testing start, etc.) → `Closed`/`Done` (set after merge by the
pod that opened the task MR — GitLab merges no longer auto-close anything,
since the ticket isn't in GitLab).

Sign-off statuses (UAT/staging QA/security/PO approval, go/no-go) use
distinctly-named columns instead of GitLab's 3-labels-together convention —
see release-manager/qa-engineer/security-engineer SKILL.md for the exact
names in use (`QA Story Tested`, `Security Cleared`, `QA UAT Approved`,
`PO UAT Approved`, `Staging QA Passed`, `Staging Security Passed`, `RM Go`) —
created once in the Kaneo project's board settings before `/kickoff` ever
runs, same one-time setup Taiga's custom statuses needed.

### Ticket assignee

Every SDLC role has its own dedicated service account in GitLab, Kaneo,
**and Authentik** (created once by `helm/ansible/playbooks/role-accounts.yml`
for GitLab/Kaneo, and `helm/authentik/provision-app-providers.py`'s
per-role loop for Authentik — all idempotent/re-runnable), so
`assignee`/assigned-to reflects which role actually did the work — not the
single shared admin identity every pod authenticated as before. The
Authentik account is for human SSO login/debugging only — it does not
change how pods authenticate. The acting API token never needs to match
the assignee: any project member's token can assign a ticket/MR to any
other member, so every pod keeps using its own role's token (or the shared
fallback) the same way it always has.

- **GitLab**: username == role name verbatim (`backend-developer`,
  `tech-lead`, ...) — deterministic, so `glab mr create --assignee
  "<own-role-name>"` needs no lookup. Membership is granted once at the
  `sdlc` GROUP level (`role-accounts.yml`), which cascades to every project
  under it automatically, present and future.
- **Kaneo**: no group-membership concept, so each new project gets every
  role added as a member individually at `/kickoff` time
  (`F-02-kickoff.json`'s "Add Role Members to Kaneo Project" step, right
  after Kaneo project creation). Resolve a role's user id via the
  project/workspace members listing, filtered by email
  `sdlc-<role>@homelab.local` (Kaneo accounts are email-keyed, not
  username-keyed like GitLab's). Stories are assigned to `project-manager`;
  tasks to whichever of `backend-developer`/`frontend-developer` the task's
  role prefix matches (`[api]` tasks fall under `backend-developer` —
  there's no separate api role account); QA/security/devops/release-manager
  tickets to their own matching role account.
- A project created **before** this migration (or before `role-accounts.yml`
  has been run at least once) won't have these memberships — back-fill by
  hand or re-run `/kickoff`'s membership step manually for it.

### Ticket points

No points/estimate field is confirmed to exist on a Kaneo task. Until one
is confirmed, PM notes a starting estimate directly in the task
description instead of a dedicated field — a placeholder for real sizing,
not a committed estimate, same role Taiga's mid-scale default played.

### GitLab compliance history

Every ticket still needs a visible GitLab activity trail for compliance,
even though tickets no longer live in GitLab. Kaneo's first-party GitLab
integration (confirmed live, merged upstream 2026-09-26) covers this —
**bidirectional** sync (task↔issue/MR, comments, status, labels), a strict
upgrade over Taiga's one-way GitLab→Taiga webhook it replaces. Configured
once per project at `/kickoff` time via Kaneo's own integration-config
endpoint (GitLab URL + an `api`-scope token + project path) — there is no
separate ansible webhook-registration playbook for this the way Taiga
needed (`taiga-gitlab-webhook.yml` is gone, not ported). Nothing in any
SKILL.md/flow needs to maintain this trail manually — it's push-based once
the integration is configured.

### MR title and description

Every MR title is prefixed with its ticket type: `[task]`, `[devops]`,
`[bugfix]`, `[qa]`, `[security]`, `[story]`, `[release]`, followed by the
ticket ref (`GL-{N}`) and a short description — e.g.
`[task] GL-42 login mechanism`.

Every MR description has exactly these sections, in order:

```markdown
## Ticket
{a real clickable link, not a bare ticket ref — Kaneo's confirmed short-link
route is /tasks/<projectSlug>-<number>; resolve `number` via
`GET $KANEO_URL/api/task/{id}` and the project's `slug` via
`GET $KANEO_URL/api/project/$KANEO_PROJECT_ID` (two separate calls, the slug
isn't inlined on the task), then link
`https://kaneo.<tailnet>/tasks/<slug>-<number>` — see backend-developer/
frontend-developer/tech-lead SKILL.md for the exact snippet}

## What's done
{bullet list of what changed}

## Proof of success
{screen recording or screenshot link — tests passing isn't proof of the
 user-visible behavior, a recording/screenshot is}

## Potential risk
{what could break, or "none identified" — never omit this section}
```

A task/bugfix MR's description also includes `Closes #{N}` on its own line —
prose only, not a live GitLab closing keyword: the ticket lives in Kaneo,
not as a GitLab issue. Kaneo's native GitLab integration is confirmed to
sync close/reopen events bidirectionally (unlike Taiga's one-way webhook),
but which side's status wins on a merge isn't yet verified against this
repo's config — until confirmed, treat the sync as the compliance-trail
comment/link only and keep doing the status flip explicitly. `{N}` is still
the exact ticket id already in the branch name. The pod that opened the MR
PATCHes the ticket's own status to `Closed`/`Done` as a separate explicit
step after
merge (see backend-developer/frontend-developer SKILL.md Step 6, and
"Ticket status" above). Story and release MRs don't use `Closes` at all
(their tickets close via a different explicit step — the release ticket
especially outlives its promote→main MR).

### MR assignee and reviewer

Every MR sets both fields at creation, never left blank:

| MR type | Assignee | Reviewer |
|---|---|---|
| Task, devops, bugfix, qa, security | `@me` (the pod that opened it) | `@me` (degenerate — same identity as assignee, since there's no distinct reviewer identity available; stands in for Tech Lead review, F-04's own review+approve step is the real gate, GitLab's reviewer field here is bookkeeping only) |
| Story | `@me` | **Edward** — look up his user id via `glab api users?search=edwardlimkoksiong1994@gmail.com`, same pattern PM already uses for group membership |
| Release | `@me` | **Edward** |

---

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
