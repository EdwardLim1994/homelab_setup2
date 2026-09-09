# Spawning agent pods from n8n

## Shape

- The `omp` chart renders one always-on `omp` Deployment **plus** a pool of
  `omp-slot-1..N` Deployments at `replicas: 0` (`values.yaml: slots.count`,
  default 3).
- Every pod runs `pod-openai.py` as PID 1: an OpenAI-compatible API on `:4096`
  backed by one persistent `omp --mode rpc` session (omp has no HTTP server of
  its own — see oh-my-pi `docs/rpc.md`). Interactive use is still
  `kubectl exec -it deploy/omp -- omp`.
- Every slot already has the `fetch-skills` initContainer wired and the
  entrypoint wrapped to copy `skills/*` from the cloned repo into
  `/root/.omp/agent/skills/` on top of the image's baked caveman/ponytail
  skills.
- n8n's `n8n` ServiceAccount gets a Role in the `omp` namespace
  (`spawner-rbac.yaml`) allowing it to `patch` deployments. n8n has no
  `kubectl` — its HTTP Request node talks to `https://kubernetes.default.svc`
  with the pod's mounted SA token.

## Flow `F-28 Spawn / Despawn Agent Pod`

`POST /webhook/spawn-agent`  `{ "name": "reviewer", "skillsRepo": "https://…" }`
1. read SA token (`executeCommand: cat …/serviceaccount/token`)
2. `GET …/deployments?labelSelector=omp.slot=free`
3. pick first free slot (error if none)
4. `PATCH` that Deployment: `replicas: 1`, `initContainers[fetch-skills].args`
   → the wanted repo, label `omp.slot: <name>`
5. returns `{ spawned, slot, service: http://omp-slot-1.omp.svc:4096 }`

`POST /webhook/despawn-agent`  `{ "name": "reviewer" }`
- find the slot labelled `omp.slot=<name>`, `PATCH` it back to
  `replicas: 0`, label `free`.

`skillsRepo` defaults to ponytail if omitted.

## Flow `F-28` — role pods (`/spawn-role`, `/despawn-role`)

Separate from the slot pool: the `omp` chart also renders one `omp-<role>`
Deployment per entry in `values.yaml: roles` (all at `replicas: 0`), each with
that role's `roles/<name>/SKILL.md` baked in via a ConfigMap mount — no git
clone.

`POST /webhook/spawn-role`  `{ "role": "backend-developer", "task": "...", "version": "...", "project": "..." }`
1. read SA token
2. validate `role` against the 12-name allowlist (mirror of `values.yaml: roles`)
3. `PATCH …/deployments/omp-<role>/scale` → `replicas: 1` (merge-patch)
4. returns `{ spawned, deployment, service, litellm, exitCode: 0 }` where
   - `service` = `http://omp-<role>.omp.svc:4096` (direct; OpenAI-compatible)
   - `litellm` = `http://litellm.litellm.svc.cluster.local:4000/omp-<role>`
     (same pod via the LiteLLM pass-through route — central auth + request
     logging; append the OpenAI sub-path, send the LiteLLM master key)

`POST /webhook/despawn-role`  `{ "role": "backend-developer" }` → scale to 0.

## omp as LiteLLM models (omp-adapter)

`helm/omp/adapter/server.py` is a scale-to-zero waker + flat proxy (own
Deployment `omp-adapter`, `values.yaml: adapter.enabled`). Each `omp-<role>`
pod already serves `POST /v1/chat/completions` (pod-openai.py); the adapter
scales the role pod to 1 on first request (own Role: `deployments/scale`
patch) and forwards the request. Model name `omp-<role>` → deployment
`omp-<role>`.

`helm/litellm/templates/config.yaml` registers one model per `ompRoles` entry
(`model: openai/omp-<role>`, `api_base:
http://omp-adapter.omp.svc:8000/v1`) plus `omp` and the two Ollama host
models. So LiteLLM's `/v1/models` lists them, and
n8n can `POST litellm/v1/chat/completions {model: "omp-tech-lead"}`.

The pod's `omp --mode rpc` session is **not** non-streaming per se, but
`pod-openai.py` accumulates the whole turn and emits it as one reply (one SSE
chunk on `stream: true`). First call to a cold role pod pays the scale-up wait
(~30–120s).

## LiteLLM pass-through routes

`helm/litellm/templates/config.yaml` renders one `pass_through_endpoints` entry
per `helm/litellm/values.yaml: ompRoles` (mirror of this chart's `roles:`):
`/omp` → the always-on pod, `/omp-<role>` → each role pod. These hit the same
OpenAI-compatible `:4096` API as the model routes — the pass-through is just an
auth'd, logged hop that does **not** wake a scaled-to-zero pod, so call
`/spawn-role` first.

The SDLC flows (F-01…F-24) call `/spawn-role` from an HTTP Request node.
`exitCode: 0` in the response keeps the downstream `$json.exitCode === 0` gate
checks working.

**Ceiling:** `/spawn-role` only scales the pod up. Running the task inside it is
done by then POSTing the task text to the pod's `/v1/chat/completions` (or via
the `omp-<role>` LiteLLM model). Each pod holds ONE rpc session, requests
serialized — a chat history of ≤ `OMP_RESET_AT` non-system messages starts a
fresh `new_session`. Add a session pool in `pod-openai.py` if one pod needs
real concurrency. The allowlist is duplicated in the flow's Code nodes; keep it
in sync with `values.yaml: roles`.

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
`cp -a /skills-src/skills/. /root/.omp/agent/skills/`. A repo without a
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

- Fixed pool, not unbounded per-name pods — each omp pod is 512Mi–2Gi.
  Raise `slots.count`, or rework `F-28` to `POST` full Deployment manifests,
  if you outgrow it.
- Slot workspace is an `emptyDir` (wiped on despawn). Give slots their own
  PVCs in `slots.yaml` if a spawned agent must keep state across runs.
- No auth on the webhooks — add an n8n header-auth credential before this is
  reachable off the tailnet.
