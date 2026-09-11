#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/list-urls.sh. Needs pwsh 7+, curl.exe.
#
# ponytail: single source of truth for "how do I reach app X", checked live.
# Apps are exposed on the tailnet by the Tailscale k8s operator (one MagicDNS
# host per app); the *.local Traefik ingresses are the LAN fallback.
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_env.ps1"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-DotEnv (Join-Path $repoRoot '.env') | Out-Null

# tailnet_domain: explicit TF_VAR_tailnet_domain wins, else derive from TS_HOST
$domain = $env:TF_VAR_tailnet_domain
if (-not $domain -and $env:TS_HOST) { $domain = ($env:TS_HOST -replace '^[^.]*\.', '') }
if (-not $domain) {
  Write-Warning "can't determine tailnet domain - set TF_VAR_tailnet_domain or TS_HOST in .env"
}

# Name ; MagicDNS host ; LAN ingress host ; path
$apps = @(
  'authentik;authentik;authentik.local;'
  'gitlab;gitlab;gitlab.local;'
  'minio (API);minio;minio.local;'
  'minio (console);minio-console;minio-console.local;'
  'n8n;n8n;;'
  'sonarqube;sonarqube;sonarqube.local;'
  'nextcloud;nextcloud;nextcloud.local;'
  'argocd;argocd;argocd.local;'
  'grafana;grafana;grafana.local;'
  'litellm;litellm;;/ui'
  'openwebui;openwebui;;'
) | ForEach-Object {
  $p = $_ -split ';'
  [pscustomobject]@{ Name = $p[0]; Host = $p[1]; Ingress = $p[2]; Path = $p[3] }
}

# ponytail: no -L — the SSO apps 302/307 to a login page (and litellm's 307
# Location is plain http, which the operator node doesn't serve); following it
# just burns the timeout. 2xx/3xx/401/403 all mean "app is up".
# Timeout: a cold nextcloud / operator-proxy first response can be slow; default
# 20s, override with $env:LIST_URLS_TIMEOUT.
$script:Timeout = if ($env:LIST_URLS_TIMEOUT) { $env:LIST_URLS_TIMEOUT } else { 20 }
function Get-HttpStatus($url) {
  $code = try { curl.exe -sk -o NUL -m $script:Timeout --connect-timeout 5 -w '%{http_code}' $url 2>$null } catch { '000' }
  switch -regex ("$code") {
    '^(2\d\d|3\d\d|401|403)$' { "OK ($code)" }
    '^0+$'                    { 'unreachable' }
    default                   { "DOWN ($code)" }
  }
}

# ponytail: the operator appends -1/-2 when the bare name is still held by a
# stale device, so read the hostname it actually assigned from the ts-<app>
# Ingress rather than constructing <app>.<domain>. Fall back to constructed.
$tsHosts = @{}
try {
  $jp = '{range .items[?(@.spec.ingressClassName=="tailscale")]}{.metadata.name}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
  (kubectl get ingress -A -o jsonpath=$jp 2>$null) -split "`n" | ForEach-Object {
    $n, $h = $_ -split "`t"
    if ($n -and $h) { $tsHosts[$n] = $h }
  }
} catch {}
function Get-TsHost($app) {
  $h = $tsHosts["ts-$app"]
  if ($h) { $h } else { "$app.$domain" }
}

$fmt = '{0,-18} {1,-45} {2,-14}'
Write-Host ($fmt -f 'APP', 'TAILSCALE (operator)', 'STATUS')
foreach ($a in $apps) {
  $tsUrl = "https://$(Get-TsHost $a.Host)$($a.Path)"
  Write-Host ($fmt -f $a.Name, $tsUrl, (Get-HttpStatus $tsUrl))
}

Write-Host ''
Write-Host 'LAN fallback (need hosts-file entry + trust the homelab CA):'
foreach ($a in $apps) {
  if ($a.Ingress) { Write-Host "  https://$($a.Ingress)  ($($a.Name))" }
}
