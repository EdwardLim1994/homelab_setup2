#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/create-cluster.sh. Needs pwsh 7+, k3d, docker.
#
# ponytail: local-path-provisioner (k3s's default StorageClass) stores PVC data
# under /var/lib/rancher/k3s/storage inside the k3d node container. k3d normally
# backs that with a Docker-managed volume, which survives a container restart but
# NOT a `k3d cluster delete`. Bind-mounting a real host directory means PVC data
# survives even a deliberate cluster delete+recreate.
[CmdletBinding()]
param([string]$ClusterName)
# ponytail: NOT 'Stop' - k3d/docker write progress to stderr, which Windows
# PowerShell 5.1 promotes to a terminating error. Gate on $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'

# ponytail: cd to repo root so a relative K3D_STORAGE_PATH (default or from
# .env) always resolves to ONE place - <repo-root>/k3d-storage - not wherever
# the caller happened to be. Absolute overrides pass through unchanged.
Set-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

if (-not $ClusterName) {
  $ClusterName = if ($env:K3D_CLUSTER_NAME) { $env:K3D_CLUSTER_NAME } else { 'internal' }
}
$storagePath = if ($env:K3D_STORAGE_PATH) { $env:K3D_STORAGE_PATH } else { './k3d-storage' }

# ponytail: `k3d cluster list <name>` exits 0 even when only the shared
# k3d-registry node is left. Check the actual server count.
function Get-ClusterServers {
  $line = k3d cluster list $ClusterName --no-headers 2>$null
  if (-not $line) { return 0 }
  # columns: NAME  SERVERS(x/y)  AGENTS  LOADBALANCER
  $servers = ($line -split '\s+')[1]
  if ($servers -match '/(\d+)') { return [int]$matches[1] }
  return 0
}

if ((Get-ClusterServers) -gt 0) {
  Write-Host "k3d cluster '$ClusterName' already exists - use 'k3d cluster start $ClusterName' to resume it, or 'k3d cluster delete $ClusterName' first if you really want to recreate it."
  # ponytail: the running cluster bind-mounts $storagePath. If it's gone or empty
  # while the cluster is up, something (usually `git clean -fdx`) deleted it and
  # every PVC mount is now broken - say so instead of looking fine.
  $sp = if ($env:K3D_STORAGE_PATH) { $env:K3D_STORAGE_PATH } else { './k3d-storage' }
  $contents = if (Test-Path $sp) { Get-ChildItem $sp -Force | Where-Object Name -ne '.gitkeep' } else { $null }
  if (-not $contents) {
    Write-Host "WARNING: '$sp' is missing/empty but the cluster is running -"
    Write-Host "         PVC data is likely lost and pods will fail on restart. Recreate:"
    Write-Host "         k3d cluster delete $ClusterName; & '$PSCommandPath' $ClusterName"
  }
  exit 0
}

# Clear a leftover 0-server entry so `k3d cluster create` won't refuse the name.
if (k3d cluster list $ClusterName 2>$null) {
  Write-Host "Removing stale '$ClusterName' entry (0 servers)..."
  k3d cluster delete $ClusterName *> $null
}

New-Item -ItemType Directory -Force $storagePath | Out-Null
$storagePathAbs = (Resolve-Path $storagePath).Path

# ponytail: the shared k3d-registry survives `k3d cluster delete` but stays
# tagged to the deleted cluster, and `k3d cluster create` refuses the name while
# any node (registry included) still claims it. Drop the registry when it's tied
# to the target name; reuse it only when another cluster owns it.
$regLine = k3d registry list --no-headers 2>$null | Where-Object { $_ -match '^k3d-registry\s' }
$regCluster = if ($regLine) { ($regLine -split '\s+')[2] } else { '' }
if ($regCluster -and $regCluster -eq $ClusterName) {
  Write-Host "Removing stale registry (tagged to '$ClusterName')..."
  k3d registry delete k3d-registry *> $null
  $regCluster = ''
}

$registryArg = if ($regCluster) {
  @('--registry-use', 'k3d-registry:5111')
} else {
  @('--registry-create', 'k3d-registry:0.0.0.0:5111')
}

# ponytail: k3d wants forward-slash host paths in --volume even on Windows
# (a bare `C:\...` splits on the drive-letter colon). Docker Desktop + WSL2
# mounts the resulting path fine. If you run rootless/Hyper-V and the bind
# mount fails, drop the --volume and accept Docker-managed volumes instead.
$volSrc = ($storagePathAbs -replace '\\', '/')
k3d cluster create $ClusterName `
  --volume "${volSrc}:/var/lib/rancher/k3s/storage@server:0" `
  --volume '/var/run/docker.sock:/var/run/docker.sock@server:0' `
  @registryArg
if ($LASTEXITCODE -ne 0) { throw "k3d cluster create failed ($LASTEXITCODE)" }

# ponytail: k3d's managed registry ships with no restart policy, so a Docker
# restart leaves it exited and every image push times out until you notice.
docker update --restart unless-stopped k3d-registry | Out-Null

Write-Host ''
Write-Host "Cluster '$ClusterName' created. PVC data persists at: $storagePathAbs"
Write-Host "Next: load .env (copy from .env.example if you haven't), then run 'tilt up'."
