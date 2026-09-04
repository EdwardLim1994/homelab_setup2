#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/gen-tfvars.sh. Needs pwsh 7+.
# Converts TF_VAR_* lines from root .env into terraform/local.auto.tfvars.
# Terraform auto-loads *.auto.tfvars, so no flags needed on terraform apply.
# Run once after editing .env.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

$lines = Get-Content .env | ForEach-Object {
  if ($_ -match '^TF_VAR_([^=]+)=(.*)$') { '{0} = "{1}"' -f $matches[1], $matches[2] }
}
$out = 'terraform/local.auto.tfvars'
Set-Content -Path $out -Value $lines -Encoding utf8
Write-Host "Generated $out ($($lines.Count) vars)"
