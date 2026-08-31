#!/usr/bin/env bash
# Wake the opencode pod, drop into its TUI, and scale it back to 0 on exit.
# ponytail: the deploy defaults to 0 replicas ("waked on demand"). This is
# the one command to remember: run it, use opencode, Ctrl+C or quit the TUI,
# and the pod idles back to 0 by itself. The EXIT trap fires on every path
# out — clean quit, Ctrl+C, kill — so the pod never gets left running.
set -euo pipefail

: "${NS:=opencode}"
: "${DEPLOY:=opencode}"

scale_down() {
  echo
  echo "Scaling ${DEPLOY} back to 0..."
  kubectl -n "$NS" scale "deploy/$DEPLOY" --replicas=0 >/dev/null
}
trap scale_down EXIT

kubectl -n "$NS" scale "deploy/$DEPLOY" --replicas=1 >/dev/null
kubectl -n "$NS" rollout status "deploy/$DEPLOY" --timeout=120s

# ponytail: no `exec` here — that would replace the shell and lose the trap.
# Run it as a child so scale_down still fires when the TUI exits.
#
# opencode temporarily disabled — run Claude Code in the pod instead. Auth is
# the CLAUDE_CODE_OAUTH_TOKEN env the chart injects (opencode-claude-auth
# Secret from TF_VAR_claude_code_token). --permission-mode auto = no prompts.
# kubectl -n "$NS" exec -it "deploy/$DEPLOY" -- opencode || true
kubectl -n "$NS" exec -it "deploy/$DEPLOY" -- claude --permission-mode auto || true
