#!/usr/bin/env bash
# Wake the omp pod, drop into its TUI, and scale it back to 0 on exit.
# ponytail: the deploy defaults to 0 replicas ("waked on demand"). This is
# the one command to remember: run it, use omp, Ctrl+C or quit the TUI,
# and the pod idles back to 0 by itself. The EXIT trap fires on every path
# out — clean quit, Ctrl+C, kill — so the pod never gets left running.
set -euo pipefail

: "${NS:=omp}"
: "${DEPLOY:=omp}"

scale_down() {
  echo
  echo "Scaling ${DEPLOY} back to 0..."
  kubectl -n "$NS" scale "deploy/$DEPLOY" --replicas=0 >/dev/null
}
trap scale_down EXIT

kubectl -n "$NS" scale "deploy/$DEPLOY" --replicas=1 >/dev/null
kubectl -n "$NS" rollout status "deploy/$DEPLOY" --timeout=120s

# ponytail: no `exec` here — that would replace the shell and lose the trap.
# Run it as a child so scale_down still fires when the TUI exits. The pod's
# PID 1 is pod-openai.py (the :4096 shim); `omp` starts the TUI alongside it.
kubectl -n "$NS" exec -it "deploy/$DEPLOY" -- omp || true
# Run Claude Code instead (auth = CLAUDE_CODE_OAUTH_TOKEN env the chart injects):
# kubectl -n "$NS" exec -it "deploy/$DEPLOY" -- claude --permission-mode auto || true
