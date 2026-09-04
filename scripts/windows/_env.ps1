#!/usr/bin/env pwsh
# Shared .env loader - dot-source this: . "$PSScriptRoot/_env.ps1"
# ponytail: pwsh has no `set -a; source .env` equivalent, so this is the
# minimum parser: KEY=VALUE lines, # comments, optional surrounding quotes.
function Import-DotEnv {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  foreach ($line in Get-Content $Path) {
    if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
      # ponytail: strip trailing ` # comment` (hash preceded by whitespace),
      # matching how bash `source .env` treats an unquoted inline comment —
      # otherwise TS_HOST / TF_VAR_tailnet_domain pick up the .env.example blurb.
      $val = ($matches[2] -replace '\s+#.*$', '').Trim()
      if ($val.Length -ge 2 -and $val[0] -eq $val[-1] -and ($val[0] -eq '"' -or $val[0] -eq "'")) {
        $val = $val.Substring(1, $val.Length - 2)
      }
      [Environment]::SetEnvironmentVariable($matches[1], $val, 'Process')
    }
  }
  return $true
}
