#!/usr/bin/env pwsh
# Trigger a one-shot ansible run in-cluster, stream its logs, let k8s reap it.
# PowerShell port of scripts/linux/ansible-run.sh. Needs pwsh 7+, kubectl.
#
# ponytail: the "ansible server" is a permanently-suspended CronJob
# (helm/ansible). This clones a Job from it and applies it; the Job's
# ttlSecondsAfterFinished deletes the pod when it's done.
#
#   scripts/windows/ansible-run.ps1                    # runs playbooks/site.yml
#   scripts/windows/ansible-run.ps1 n8n                # runs playbooks/n8n.yml
#   scripts/windows/ansible-run.ps1 n8n --syntax-check # parse-only
[CmdletBinding()]
param(
  [string]$Playbook = 'site',
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$AnsibleArgs
)
# ponytail: NOT 'Stop' - Windows PowerShell 5.1 turns every native-command
# stderr line into a terminating error, and kubectl chats on stderr constantly
# (progress, "no matching resources found" while a pod is still scheduling).
# Correctness comes from checking $LASTEXITCODE where it actually matters.
$ErrorActionPreference = 'Continue'

$ns = if ($env:NS) { $env:NS } else { 'ansible' }
$cronjob = if ($env:CRONJOB) { $env:CRONJOB } else { 'ansible-runner' }
$pbArgs = ($AnsibleArgs -join ' ')
$job = "ansible-$Playbook-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

# ponytail: `kubectl set env --local` rewrites the env in the rendered manifest
# offline - no jq, no post-create race.
kubectl -n $ns create job $job --from="cronjob/$cronjob" --dry-run=client -o yaml |
  kubectl set env --local -f - -o yaml "PLAYBOOK=$Playbook.yml" "ANSIBLE_ARGS=$pbArgs" |
  kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "failed to create job $job" }

Write-Host "Job $job created - waiting for pod..."

# ponytail: poll for the pod instead of `kubectl wait` - wait exits non-zero
# with "no matching resources found" when the pod hasn't been scheduled yet.
$pod = $null
foreach ($i in 1..60) {
  $pod = kubectl -n $ns get pod -l "job-name=$job" -o name 2>$null | Select-Object -First 1
  if ($pod) { break }
  Start-Sleep 2
}
if (-not $pod) { Write-Host "pod never appeared - inspect: kubectl -n $ns describe job/$job"; exit 1 }

kubectl -n $ns wait --for=condition=ready "$pod" --timeout=120s 2>$null
kubectl -n $ns logs -f "job/$job" 2>$null

kubectl -n $ns wait --for=condition=complete "job/$job" --timeout=600s 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host 'Job complete.'
  kubectl -n $ns delete job $job --ignore-not-found 2>$null | Out-Null
} else {
  Write-Host "Job FAILED - inspect with: kubectl -n $ns describe job/$job"
  exit 1
}
