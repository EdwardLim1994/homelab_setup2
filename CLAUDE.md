# CLAUDE.md

Project structure, conventions, and current progress live in **[AGENT.md](./AGENT.md)** —
read it first. This file adds Claude-Code-specific notes.

@AGENT.md

## Working here

- **Tilt path and Terraform path must stay in sync.** If you touch
  `helm/<app>/Tiltfile` or `helm/<app>/values.yaml`, make the matching change
  in `terraform/<app>.tf`, and vice versa.
- Secrets flow one way: edit `.env` → `scripts/linux/gen-tfvars.sh` →
  `tofu apply`. Never edit `terraform/local.auto.tfvars` or a live Secret
  directly. `helm/<app>/values.yaml` carries `__PLACEHOLDER__` tokens the
  `.tf` swaps in.
- `ponytail:` comments are intentional. Don't remove a simplification without
  a reason; if you do change one, update the comment.
- Prefer editing `values.yaml` + `tofu apply` over `kubectl set env` /
  `kubectl patch`. Live-only changes drift from the repo.

## This environment

- **caveman + ponytail rulesets are active** (see the session banners) — terse
  prose, laziest-solution-that-works. They govern chat/output style and build
  decisions, not committed code/comments/docs (those stay normal prose).
- Auto-memory lives under `.claude/projects/.../memory/` — check `MEMORY.md`
  for prior findings (e.g. the `opencode → omp` migration note).
- Some `tofu apply` / `kubectl` mutations get blocked by the auto-mode
  classifier. When that happens, make the file changes and hand the user the
  exact commands to run.

## Gotchas found the hard way

- `omp --mode rpc` ignores `config.yml`'s `model:` — it must be passed
  `--model` (done in `pod-openai.py`), and the pod's `models.db` must be
  populated with `omp models refresh` first.
- omp's `models.yml` for v18.x: `baseUrl` **without** `/v1`, and
  `auth: none` on the ollama provider, or discovery silently returns nothing.
- `qwen3-coder-next` (80B) OOMs on the host — use `qwen3.8:27b`.
- n8n blocks `$env` in node expressions by default
  (`N8N_BLOCK_ENV_ACCESS_IN_NODE`).
- n8n 2.x rejects `active`/`tags` on `POST /workflows`; activate via
  `POST /workflows/{id}/activate`.
- Mattermost `mmctl bot create` doesn't work in `--local` mode.
- Git Bash rewrites `/mattermost/...` paths passed to `kubectl exec` — prefix
  the command with `MSYS_NO_PATHCONV=1`.
