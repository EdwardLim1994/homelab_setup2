#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/dev-up.sh. Needs pwsh 7+, tilt.
#
# ponytail: `tilt up` on its own doesn't read .env - run it directly and
# GITHUB_OAUTH_CLIENT_ID/SECRET (and everything else in .env) silently fall back
# to dev placeholders, breaking GitHub login. This wrapper is the one thing to
# remember instead of the export incantation.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$TiltArgs)
# ponytail: NOT 'Stop' - `tilt up` streams warnings to stderr for hours; under
# Stop the first one kills the wrapper. Its own exit code is propagated below.
$ErrorActionPreference = 'Continue'

. "$PSScriptRoot/_env.ps1"
Set-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

if (-not (Import-DotEnv '.env')) {
  Write-Warning 'no .env found (copy .env.example to .env for real secrets like GitHub OAuth).'
}

tilt up --host 0.0.0.0 @TiltArgs
exit $LASTEXITCODE
