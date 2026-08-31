# Spawning agent pods from n8n

## Shape

- The `opencode` chart renders one always-on `opencode` Deployment **plus** a
  pool of `opencode-slot-1..N` Deployments at `replicas: 0`
  (`values.yaml: slots.count`, default 3).
- Every slot already has the `fetch-skills` initContainer wired and the
  entrypoint wrapped to copy `skills/*` from the cloned repo into
  `/root/.config/opencode/skills/` on top of the image's baked
  caveman/ponytail skills.
- n8n's `n8n` ServiceAccount gets a Role in the `opencode` namespace
  (`spawner-rbac.yaml`) allowing it to `patch` deployments. n8n has no
  `kubectl` — its HTTP Request node talks to `https://kubernetes.default.svc`
  with the pod's mounted SA token.

## Flow `F-28 Spawn / Despawn Agent Pod`

`POST /webhook/spawn-agent`  `{ "name": "reviewer", "skillsRepo": "https://…" }`
1. read SA token (`executeCommand: cat …/serviceaccount/token`)
2. `GET …/deployments?labelSelector=opencode.slot=free`
3. pick first free slot (error if none)
4. `PATCH` that Deployment: `replicas: 1`, `initContainers[fetch-skills].args`
   → the wanted repo, label `opencode.slot: <name>`
5. returns `{ spawned, slot, service: http://opencode-slot-1.opencode.svc:4096 }`

`POST /webhook/despawn-agent`  `{ "name": "reviewer" }`
- find the slot labelled `opencode.slot=<name>`, `PATCH` it back to
  `replicas: 0`, label `free`.

`skillsRepo` defaults to ponytail if omitted.

## Flow `F-28` — role pods (`/spawn-role`, `/despawn-role`)

Separate from the slot pool: the `opencode` chart also renders one
`opencode-<role>` Deployment per entry in `values.yaml: roles` (all at
`replicas: 0`), each with that role's `roles/<name>/SKILL.md` baked in via a
ConfigMap mount — no git clone.

`POST /webhook/spawn-role`  `{ "role": "backend-developer", "task": "...", "version": "...", "project": "..." }`
1. read SA token
2. validate `role` against the 12-name allowlist (mirror of `values.yaml: roles`)
3. `PATCH …/deployments/opencode-<role>/scale` → `replicas: 1` (merge-patch)
4. returns `{ spawned, deployment, service, litellm, exitCode: 0 }` where
   - `service` = `http://opencode-<role>.opencode.svc:4096` (direct)
   - `litellm` = `http://litellm.litellm.svc.cluster.local:4000/opencode-<role>`
     (same pod via the LiteLLM pass-through route — central auth + request
     logging; append the opencode API sub-path, send the LiteLLM master key)

`POST /webhook/despawn-role`  `{ "role": "backend-developer" }` → scale to 0.

## opencode as LiteLLM models (opencode-adapter)

`helm/opencode/adapter/server.py` is an OpenAI-compatible shim (own Deployment
`opencode-adapter`, `values.yaml: adapter.enabled`). It turns
`POST /v1/chat/completions {model: "opencode-<role>"}` into opencode's
`POST /session` + `POST /session/:id/message`, and scales the role pod to 1
first (own Role: `deployments/scale` patch).

`helm/litellm/templates/config.yaml` registers one model per
`opencodeRoles` entry (`model: openai/opencode-<role>`, `api_base:
http://opencode-adapter.opencode.svc:8000/v1`) plus `opencode` and the two
Ollama host models. So LiteLLM's `/v1/models` — and OpenWebUI's picker — list
them, and n8n can `POST litellm/v1/chat/completions {model: "opencode-tech-lead"}`.

Non-streaming (whole reply at once). First call to a cold role pod pays the
scale-up wait (~30–120s).

## LiteLLM pass-through routes

`helm/litellm/templates/config.yaml` renders one `pass_through_endpoints` entry
per `helm/litellm/values.yaml: opencodeRoles` (mirror of this chart's `roles:`):
`/opencode` → the always-on pod, `/opencode-<role>` → each role pod. These are
NOT models (opencode serve isn't OpenAI-shaped) — just an auth'd, logged hop.
Role pods are scale-to-zero: `/spawn-role` first, LiteLLM won't wake them.

The SDLC flows (F-01…F-24) call `/spawn-role` from an HTTP Request node where
they used to shell out to `omp run`. `exitCode: 0` in the response keeps the
downstream `$json.exitCode === 0` gate checks working.

**Ceiling:** `/spawn-role` only scales the pod up — it does **not** yet run the
task inside it. Wiring the task to opencode's `serve` job API (what `omp` was
meant to wrap) is still open. The allowlist is duplicated in the flow's Code
nodes; keep it in sync with `values.yaml: roles`.

## Skills repo layout (still to create)

```
<repo>/
  skills/
    <skill-name>/
      SKILL.md          # frontmatter + body, same format as caveman/ponytail
    <another-skill>/
      SKILL.md
```

The initContainer does `git clone --depth 1 <repo> /skills-src`; the pod runs
`cp -a /skills-src/skills/. /root/.config/opencode/skills/`. A repo without a
top-level `skills/` dir just no-ops (the `cp` is `|| true`).

**In-cluster clone URL, not the tailnet name.** GitLab SSH (port 22) is not
exposed on the tailnet, and the tailnet name round-trips out of the cluster
and back. Pods clone GitLab over HTTP by Service DNS:

```
http://gitlab-webservice-default.gitlab.svc:8181/<group>/<repo>.git
```

Private repo — create a Project Access Token (role: Reporter, scope:
`read_repository`) and prefix it:

```
http://oauth2:<token>@gitlab-webservice-default.gitlab.svc:8181/<group>/<repo>.git
```

`slots.defaultSkillsRepo` in `values.yaml` is already set to the in-cluster
URL for `EdwardLim1994/internal-agent-skills`; add the token prefix if the
repo is private.

## Limits / when to change

- Fixed pool, not unbounded per-name pods — each opencode pod is 512Mi–2Gi.
  Raise `slots.count`, or rework `F-28` to `POST` full Deployment manifests,
  if you outgrow it.
- Slot workspace is an `emptyDir` (wiped on despawn). Give slots their own
  PVCs in `slots.yaml` if a spawned agent must keep state across runs.
- No auth on the webhooks — add an n8n header-auth credential before this is
  reachable off the tailnet.
