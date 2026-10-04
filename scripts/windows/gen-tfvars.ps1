#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/gen-tfvars.sh. Needs pwsh 7+.
# Converts TF_VAR_* lines from root .env into terraform/<env>/local.auto.tfvars,
# one per root module (internal/sit/uat/production). Terraform auto-loads
# *.auto.tfvars, so no flags needed on terraform apply. Run once after editing .env.
#
# ponytail: each env only gets the TF_VAR_* lines it actually declares a
# `variable "<name>"` for - a full copy into every dir would trip the
# "undeclared variable" warning CLAUDE.md already calls out.
$ErrorActionPreference = 'Stop'

# ponytail: absolute paths off $PSScriptRoot — no Set-Location, so the caller's
# shell stays where it was.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile = Join-Path $repoRoot '.env'

$envLines = Get-Content $envFile | Where-Object { $_ -match '^TF_VAR_([^=]+)=(.*)$' } | ForEach-Object {
  if ($_ -match '^TF_VAR_([^=]+)=(.*)$') { [PSCustomObject]@{ Name = $matches[1]; Line = '{0} = "{1}"' -f $matches[1], $matches[2] } }
}

foreach ($env in @('internal', 'sit', 'uat', 'production')) {
  $envDir = Join-Path $repoRoot "terraform/$env"
  if (-not (Test-Path $envDir)) { continue }
  $declared = Get-ChildItem $envDir -Filter '*.tf' | Get-Content | Select-String 'variable\s+"([^"]+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value }
  $out = Join-Path $envDir 'local.auto.tfvars'
  $lines = $envLines | Where-Object { $declared -contains $_.Name } | ForEach-Object { $_.Line }
  Set-Content -Path $out -Value $lines -Encoding utf8
  Write-Host "Generated $out ($($lines.Count) vars)"
}
