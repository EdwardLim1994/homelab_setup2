#!/usr/bin/env pwsh
# Local port-forwards for the terraform-deployed apps (Tilt does this itself).
#
# Browser / SSO: use the TAILNET column - https://<app>.<tailnet_domain>, served
# by the Tailscale k8s operator (terraform/tailscale-ingress.tf). Every OIDC app
# (argocd, openwebui, litellm, grafana, gitlab, nextcloud) bakes that exact
# origin into its redirect_uri, so logging in through the localhost forward or a
# `tailscale serve` port fails ("redirect_uri mismatch" / "Invalid redirect URL").
#
# The localhost forwards below are for non-browser access only - S3 clients,
# `argocd` CLI, psql, curl - where the Host header doesn't matter.
#
# ponytail: NOT 'Stop' - kubectl port-forward chats on stderr, terminating under
# Windows PowerShell 5.1.
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot/_env.ps1"
Import-DotEnv (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.env') | Out-Null

# tailnet domain: explicit TF_VAR_tailnet_domain wins, else derive from TS_HOST
$domain = $env:TF_VAR_tailnet_domain
if (-not $domain -and $env:TS_HOST) { $domain = ($env:TS_HOST -replace '^[^.]*\.', '') }
if (-not $domain) { Write-Warning 'no TF_VAR_tailnet_domain / TS_HOST - TAILNET column will be blank' }

# name ; namespace ; service ; svc-port ; local-port ; magicdns-slug ; path
$apps = @(
  'authentik;authentik;authentik-server;80;9000;authentik;'
  'gitlab;gitlab;gitlab-webservice-default;8181;8181;gitlab;'
  'minio (API);minio;minio;9000;9002;minio;'
  'minio (browser);minio;minio-console;9001;9003;minio-console;'
  'n8n;n8n;n8n;5678;5678;n8n;'
  'sonarqube;sonarqube;sonarqube-sonarqube;9000;9010;sonarqube;'
  'nextcloud;nextcloud;nextcloud;8080;8082;nextcloud;'
  'argocd;argocd;argocd-server;80;9001;argocd;'
  'grafana;observability;observability-grafana;80;3000;grafana;'
  'openwebui;openwebui;openwebui;8080;8080;openwebui;'
  'litellm;litellm;litellm;4000;4000;litellm;/ui'
) | ForEach-Object {
  $p = $_ -split ';'
  [pscustomobject]@{ Name=$p[0]; Ns=$p[1]; Svc=$p[2]; SvcPort=$p[3]; LocalPort=$p[4]; Slug=$p[5]; Path=$p[6] }
}

function Check($url) {
  try { curl.exe -sk -o NUL -m 3 -w '%{http_code}' $url 2>$null } catch { '' }
}

$pwsh = (Get-Process -Id $PID).Path
$procs = @()
try {
  # ponytail: kubectl port-forward drops on idle resets / apiserver blips.
  # Respawn loop self-heals within ~2s. Each loop is its own pwsh process (not
  # Start-Job) so teardown is one Kill($true) per app — no per-runspace
  # Remove-Job -Force, no cold Win32_Process WMI scan for orphaned kubectl.exe,
  # which is what made Ctrl+C take several seconds.
  foreach ($a in $apps) {
    $loop = "while (`$true) { kubectl port-forward -n $($a.Ns) `"svc/$($a.Svc)`" `"$($a.LocalPort):$($a.SvcPort)`" *> `$null; Start-Sleep 2 }"
    $procs += Start-Process $pwsh -ArgumentList '-NoProfile', '-Command', $loop -PassThru -WindowStyle Hidden
  }

  Write-Host 'waiting for port-forwards to come up...'
  Start-Sleep 3

  $fmt = '{0,-18} {1,-32} {2,-8} {3,-45} {4,-8}'
  Write-Host ($fmt -f 'APP', 'LOCALHOST (CLI/debug only)', 'STATUS', 'TAILNET (browser/SSO)', 'STATUS')
  foreach ($a in $apps) {
    $localUrl = "http://localhost:$($a.LocalPort)$($a.Path)"
    $tsUrl = if ($domain) { "https://$($a.Slug).$domain$($a.Path)" } else { '' }
    Write-Host ($fmt -f $a.Name, $localUrl, (Check $localUrl), $tsUrl, ($(if ($tsUrl) { Check $tsUrl } else { '' })))
  }

  Write-Host "`nport-forwards running, Ctrl+C to stop"
  while ($true) { Start-Sleep 1 }
}
finally {
  Write-Host "`nstopping port-forwards..."
  # Kill($true) = kill the whole tree (wrapper pwsh + its kubectl child).
  foreach ($p in $procs) { try { $p.Kill($true) } catch {} }
}
