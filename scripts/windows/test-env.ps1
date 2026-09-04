#!/usr/bin/env pwsh
# Self-check for _env.ps1's Import-DotEnv. Run: pwsh scripts/windows/test-env.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_env.ps1"

$tmp = New-TemporaryFile
@'
# comment line
PLAIN=hello
QUOTED="a b c"
SQUOTED='x y'
WITH_EQ=key=val
  SPACED = trimmed
'@ | Set-Content -Path $tmp -Encoding utf8

Import-DotEnv $tmp.FullName | Out-Null
Remove-Item $tmp

function Expect($name, $want) {
  $got = [Environment]::GetEnvironmentVariable($name, 'Process')
  if ($got -ne $want) { throw "FAIL $name : want [$want] got [$got]" }
}
Expect PLAIN   'hello'
Expect QUOTED  'a b c'
Expect SQUOTED 'x y'
Expect WITH_EQ 'key=val'
Expect SPACED  'trimmed'
if (Import-DotEnv (Join-Path ([IO.Path]::GetTempPath()) 'nope-does-not-exist.env')) {
  throw 'FAIL: missing file should return $false'
}
Write-Host 'ok - Import-DotEnv'
