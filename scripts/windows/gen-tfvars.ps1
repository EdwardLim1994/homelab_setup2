#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/gen-tfvars.sh. Needs pwsh 7+.
# Converts TF_VAR_* lines from root .env into terraform/local.auto.tfvars.
# Terraform auto-loads *.auto.tfvars, so no flags needed on terraform apply.
# Run once after editing .env.
$ErrorActionPreference = 'Stop'

# ponytail: absolute paths off $PSScriptRoot — no Set-Location, so the caller's
# shell stays where it was.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile = Join-Path $repoRoot '.env'
$out = Join-Path $repoRoot 'terraform/local.auto.tfvars'

$lines = Get-Content $envFile | ForEach-Object {
  if ($_ -match '^TF_VAR_([^=]+)=(.*)$') { '{0} = "{1}"' -f $matches[1], $matches[2] }
}
Set-Content -Path $out -Value $lines -Encoding utf8
Write-Host "Generated $out ($($lines.Count) vars)"
