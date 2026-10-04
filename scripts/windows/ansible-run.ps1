#!/usr/bin/env pwsh
# Trigger one-shot ansible runs in-cluster, stream logs, let k8s reap the pods.
# PowerShell port of scripts/linux/ansible-run.sh. Needs pwsh 7+, kubectl.
#
# ponytail: the "ansible server" is a permanently-suspended CronJob
# (helm/ansible). This clones a Job from it and applies it; the Job's
# ttlSecondsAfterFinished deletes the pod when it's done.
#
#   scripts/windows/ansible-run.ps1                    # ALL playbooks, in parallel
#   scripts/windows/ansible-run.ps1 n8n                # runs playbooks/n8n.yml
#   scripts/windows/ansible-run.ps1 n8n --syntax-check # parse-only
#
# ponytail: no-arg fans out one child process per playbook instead of the
# serial site.yml. Independent playbooks (own namespace each) run
# concurrently. Pass a playbook name explicitly (or `site`) to run just that one.
[CmdletBinding()]
param(
  [string]$Playbook = '',
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$AnsibleArgs
)
# ponytail: NOT 'Stop' - Windows PowerShell 5.1 turns every native-command
# stderr line into a terminating error, and kubectl chats on stderr constantly
# (progress, "no matching resources found" while a pod is still scheduling).
# Correctness comes from checking $LASTEXITCODE where it actually matters.
$ErrorActionPreference = 'Continue'

if ($Playbook -eq '-h' -or $Playbook -eq '--help' -or $Playbook -eq '-help') {
@'
Usage: scripts\windows\ansible-run.ps1 [playbook] [ansible-args...]
       scripts\windows\ansible-run.ps1 --help | -h

Clones a one-shot Job from the suspended ansible-runner CronJob (helm/ansible),
streams its logs, lets k8s reap the pod when done.

With no argument: runs every playbook in the default fan-out, in parallel.
Pass "site" to run the same set serially instead. Pass a playbook name to
run just that one (including bootstrap/DR-only ones, never run by default).

Common ansible-args: --syntax-check (parse-only, no changes), --tags <tag>,
-e key=value (extra vars).

DEFAULT FAN-OUT (no arg runs all of these, in parallel):
  n8n                   n8n post-deploy: owner setup, mint/reuse API key, seed the SDLC flows
  omp                   Push a GitLab token into every omp pod's env
  litellm               Wait for the LiteLLM proxy, confirm models loaded
  mcp-servers           Push access tokens from .env into each MCP server Deployment
  openwebui             Install the SDLC pipe as an OpenWebUI Function (idempotent)

  site                  Run the exact same set SERIALLY instead of in parallel

BOOTSTRAP / DISASTER-RECOVERY (not in the default fan-out -- run explicitly):
  gitlab-webhook        Register/verify/deregister the n8n SDLC router webhook (F-00) on
                        every sdlc-group project (--tags verify | --tags deregister
                        -e deregister_confirmed=true)
  taiga-gitlab-webhook  Register Taiga's own GitLab integration webhook (compliance
                        trail -- separate from gitlab-webhook's F-00 router hook)
  sonarqube-gitlab      Configure SonarQube's GitLab DevOps Platform Integration
  argocd-clusters       Register the phase k3d clusters (sit/uat/qa/staging/production) with ArgoCD
  role-accounts         Create one GitLab + Taiga service account per SDLC role
                        (idempotent, re-run-safe -- see AGENTS.md's "Ticket assignee")

Examples:
  scripts\windows\ansible-run.ps1
  scripts\windows\ansible-run.ps1 n8n
  scripts\windows\ansible-run.ps1 n8n --syntax-check
  scripts\windows\ansible-run.ps1 gitlab-webhook --tags verify
  scripts\windows\ansible-run.ps1 role-accounts
'@ | Write-Host
  exit 0
}

$ns = if ($env:NS) { $env:NS } else { 'ansible' }
$cronjob = if ($env:CRONJOB) { $env:CRONJOB } else { 'ansible-runner' }

# --- no arg: run everything, in parallel -----------------------------------
if (-not $Playbook -or $Playbook -eq 'all') {
  $parallel = @('n8n', 'omp', 'litellm', 'mcp-servers', 'openwebui')
  $chains = @()   # each: serial, stop on first failure. Empty now that
                   # mattermost (the only chained-after-n8n playbook) is gone.
  # ponytail: re-invoke the *same* shell that's running this (pwsh 7 or Windows
  # PowerShell 5.1) - `pwsh` isn't always on PATH.
  $self = (Get-Process -Id $PID).Path
  $extra = if ($AnsibleArgs) { $AnsibleArgs -join ' ' } else { '' }
  $rest = if ($AnsibleArgs) { $AnsibleArgs } else { @() }
  $procs = @()

  foreach ($p in $parallel) {
    $a = @('-NoProfile', '-File', $PSCommandPath, $p) + $rest
    $procs += Start-Process $self -PassThru -NoNewWindow -ArgumentList $a
  }
  foreach ($c in $chains) {
    $seq = ($c | ForEach-Object { "& '$PSCommandPath' $_ $extra; if (`$LASTEXITCODE) { exit 1 }" }) -join '; '
    $procs += Start-Process $self -PassThru -NoNewWindow -ArgumentList @('-NoProfile', '-Command', $seq)
  }

  $procs = $procs | Where-Object { $_ }
  $procs | Wait-Process
  $failed = $procs | Where-Object ExitCode -ne 0
  if ($failed) { Write-Host "FAILED: $($failed.Count) playbook run(s)"; exit 1 }
  Write-Host 'All playbooks complete.'
  exit 0
}

# --- single playbook ------------------------------------------------------
$pbArgs = ($AnsibleArgs -join ' ')
$job = "ansible-$Playbook-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-$(Get-Random -Maximum 99999)"

# ponytail: `kubectl set env --local` rewrites the env in the rendered manifest
# offline - no jq, no post-create race.
kubectl -n $ns create job $job --from="cronjob/$cronjob" --dry-run=client -o yaml |
  kubectl set env --local -f - -o yaml "PLAYBOOK=$Playbook.yml" "ANSIBLE_ARGS=$pbArgs" |
  kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "failed to create job $job" }

Write-Host "[$Playbook] Job $job created - waiting for pod..."

# ponytail: poll for the pod instead of `kubectl wait` - wait exits non-zero
# with "no matching resources found" when the pod hasn't been scheduled yet.
$pod = $null
foreach ($i in 1..60) {
  $pod = kubectl -n $ns get pod -l "job-name=$job" -o name 2>$null | Select-Object -First 1
  if ($pod) { break }
  Start-Sleep 2
}
if (-not $pod) { Write-Host "[$Playbook] pod never appeared - inspect: kubectl -n $ns describe job/$job"; exit 1 }

# ponytail: `kubectl logs -f` can block forever (pod stuck ContainerCreating,
# backoffLimit retry, TTL reap mid-stream). Run it as a killable child and let
# the status poll below be the authority on "done".
$podName = ($pod -replace '^pod/', '')
$self = (Get-Process -Id $PID).Path
# ponytail: the -Command string must not embed double quotes — Start-Process's
# ArgumentList-to-command-line quoting mishandles nested " inside an argument
# that already needs quoting for its spaces, truncating it early. The
# fragment that survives ("[n8n] ...") then gets parsed by the child
# powershell.exe as top-level script text, where a bare [n8n] is a
# type-literal expression -> "Unable to find type [n8n]." Single-quoted
# literal + string concat avoids embedding any " at all.
$logProc = Start-Process $self -PassThru -NoNewWindow -ArgumentList @(
  '-NoProfile', '-Command',
  "kubectl -n $ns logs -f $podName 2>`$null | ForEach-Object { '[$Playbook] ' + `$_ }"
)

# ponytail: poll the job's terminal condition. A job that TTL-reaps after
# succeeding disappears entirely - treat "gone" as complete, not a hang. A
# single failed `kubectl get job` is frequently just a transient API-server
# blip (TLS handshake timeout, brief network flake), NOT proof the job
# vanished - require 3 CONSECUTIVE failures before concluding that, and
# track every blip so the final RESULT line can flag "succeeded, but polling
# was flaky" instead of silently hiding it.
$rc = 1
$seen = ''
$goneStreak = 0
$blips = 0
foreach ($i in 1..400) {
  kubectl -n $ns get job $job 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    $goneStreak++; $blips++
    if ($goneStreak -lt 3) { Start-Sleep 2; continue }
    if ($seen -match '\bComplete\b') { $rc = 0 } else { $rc = 1 }
    break
  }
  $goneStreak = 0
  $types = kubectl -n $ns get job $job -o "jsonpath={.status.conditions[*].type}" 2>$null
  if (-not $types) { $blips++ }
  $seen = $types
  if ($types -match '\bComplete\b') {
    kubectl -n $ns delete job $job --ignore-not-found 2>$null | Out-Null
    $rc = 0; break
  }
  if ($types -match '\bFailed\b') { $rc = 1; break }
  if ($i % 40 -eq 0) { Write-Host "[$Playbook] ...still running ($($i * 3)s)" }
  Start-Sleep 3
}
if ($logProc -and -not $logProc.HasExited) { Stop-Process -Id $logProc.Id -Force 2>$null }

if ($i -ge 400) {
  Write-Host "[$Playbook] RESULT: FAILED - timed out after 20m - kubectl -n $ns describe job/$job"
  exit 1
}
if ($rc -eq 0) {
  if ($blips -gt 0) {
    Write-Host "[$Playbook] RESULT: WARNING - job Complete, but $blips transient kubectl API blip(s) occurred while polling (not a real failure; verify yourself if unsure: kubectl -n $ns get job $job -o yaml)"
  } else {
    Write-Host "[$Playbook] RESULT: SUCCESS - job Complete"
  }
} else {
  if ($goneStreak -ge 3) {
    $lastSeen = if ($seen) { $seen } else { 'none' }
    Write-Host "[$Playbook] RESULT: FAILED - job genuinely vanished (confirmed gone across 3 consecutive checks, last seen condition: '$lastSeen') - kubectl -n $ns get events"
  } else {
    Write-Host "[$Playbook] RESULT: FAILED - job condition Failed - kubectl -n $ns describe job/$job"
  }
}
exit $rc
