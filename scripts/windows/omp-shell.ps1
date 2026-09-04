#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/omp-shell.sh. Needs pwsh 7+, kubectl.
#
# Wake the omp pod, drop into its TUI, and scale it back to 0 on exit.
# ponytail: the deploy defaults to 0 replicas ("waked on demand"). Run this, use
# the tool, quit - the finally block scales back to 0 on every path out.
# ponytail: NOT 'Stop' - kubectl rollout/exec write to stderr; WinPS 5.1 would
# make that terminating and skip the finally-block scale-down.
$ErrorActionPreference = 'Continue'

$ns = if ($env:NS) { $env:NS } else { 'omp' }
$deploy = if ($env:DEPLOY) { $env:DEPLOY } else { 'omp' }

try {
  kubectl -n $ns scale "deploy/$deploy" --replicas=1 | Out-Null
  kubectl -n $ns rollout status "deploy/$deploy" --timeout=120s

  # The pod's PID 1 is pod-openai.py (the :4096 shim); `omp` starts the TUI
  # alongside it. Run Claude Code instead with the commented line (auth =
  # CLAUDE_CODE_OAUTH_TOKEN env the chart injects).
  kubectl -n $ns exec -it "deploy/$deploy" -- omp
  # kubectl -n $ns exec -it "deploy/$deploy" -- claude --permission-mode auto
}
finally {
  Write-Host ''
  Write-Host "Scaling $deploy back to 0..."
  kubectl -n $ns scale "deploy/$deploy" --replicas=0 | Out-Null
}
