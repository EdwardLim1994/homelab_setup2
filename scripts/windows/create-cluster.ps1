#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/create-cluster.sh. Needs pwsh 7+, k3d, docker.
#
# ponytail: local-path-provisioner (k3s's default StorageClass) stores PVC data
# under /var/lib/rancher/k3s/storage inside the k3d node container. k3d normally
# backs that path with a Docker-managed volume, which survives a container
# restart — but NOT a `k3d cluster delete` (delete removes its volumes by
# design). We back it with a NAMED Docker volume instead (not owned by the
# node's lifecycle, so it survives delete+recreate same as a host bind-mount
# would) — this is what actually happened once already in this repo's history
# (all app data + Authentik's config wiped).
#
# ponytail: was a bind-mount to ./k3d-storage on the Windows host. Docker
# Desktop's Windows<->WSL2 9p filesystem boundary is flaky across host
# sleep/restart — postgres hit "Input/output error" on its data files after
# a Docker Desktop restart, cascading down every app sharing that DB. A named
# Docker volume lives inside the Desktop VM's own disk, no 9p hop.
[CmdletBinding()]
param([string]$ClusterName)
# ponytail: NOT 'Stop' - k3d/docker write progress to stderr, which Windows
# PowerShell 5.1 promotes to a terminating error. Gate on $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'

# ponytail: cd to repo root so relative refs (.env, this script re-invoking
# itself for "phases") always resolve to ONE place, not wherever the caller
# happened to be. Push/Pop so a dot-sourced run (`. .\create-cluster.ps1`)
# leaves the caller's own location alone once this finishes — try/finally
# covers every exit/throw.
Push-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
try {

# Harbor's NodePort (harbor Service), host-mapped on k3d-internal's
# loadbalancer. The phase clusters (sit/uat/production) sit on their own
# docker networks and can't reach harbor.harbor.svc.cluster.local
# directly - Docker Desktop's host.docker.internal is reachable from every
# container on every network, so that's the hop. Same port must still be
# wired to the harbor Service as a NodePort (helm/harbor or a one-off
# Service, not this script's job) for any of this to actually resolve.
$RegistryMirrorPort = if ($env:REGISTRY_MIRROR_PORT) { $env:REGISTRY_MIRROR_PORT } else { '30500' }
# Same host.docker.internal bridge, for sit/uat/production's opencost to
# remote_write into internal's Mimir (terraform/internal/observability.tf's
# mimir_distributor_nodeport Service is the other half of this bridge).
$MimirPushPort = if ($env:MIMIR_PUSH_PORT) { $env:MIMIR_PUSH_PORT } else { '30510' }
# Same bridge, for sit/uat/production's log-shipper to push logs into
# internal's Loki (terraform/internal/observability.tf's loki_nodeport
# Service is the other half).
$LokiPushPort = if ($env:LOKI_PUSH_PORT) { $env:LOKI_PUSH_PORT } else { '30511' }
# Same bridge, for sit/uat/production's log-shipper to push traces into
# internal's Tempo (terraform/internal/observability.tf's tempo_nodeport
# Service is the other half).
$TempoPushPort = if ($env:TEMPO_PUSH_PORT) { $env:TEMPO_PUSH_PORT } else { '30512' }

# One argument creates a single named cluster (unchanged, default "internal").
# "phases" creates the 3 phase clusters, each with a containerd mirror config.
if ($ClusterName -eq 'phases') {
  foreach ($phase in @('sit', 'uat', 'production')) {
    Write-Host "=== $phase ==="
    & $PSCommandPath $phase
  }
  exit 0
}

if (-not $ClusterName) {
  $ClusterName = if ($env:K3D_CLUSTER_NAME) { $env:K3D_CLUSTER_NAME } else { 'internal' }
}
$isPhaseCluster = @('sit', 'uat', 'production') -contains $ClusterName
# ponytail: named Docker volume, not a host path — one per cluster name so
# separate clusters don't share storage. Override via $env:K3D_STORAGE_VOLUME.
$storageVolume = if ($env:K3D_STORAGE_VOLUME) { $env:K3D_STORAGE_VOLUME } else { "k3d-$ClusterName-storage" }

# host.docker.internal bridge for internal's kafka-ui to reach THIS cluster's
# kafka (terraform/modules/platform-apps/kafka.tf's kafka-external NodePort
# Service). One host port per phase cluster since they share the same Docker
# host — must match terraform/{sit,uat,production}/main.tf's kafka_nodeport
# and helm/kafka-ui/values.yaml's bootstrapServers.
$KafkaNodePort = if ($env:KAFKA_NODEPORT) { $env:KAFKA_NODEPORT } else {
  switch ($ClusterName) {
    'sit' { '30901' }
    'uat' { '30902' }
    'production' { '30903' }
    default { $null }
  }
}

# Same bridge, for GitLab CI (internal) pushing schemas to THIS cluster's
# Apicurio (terraform/modules/platform-apps/apicurio.tf's apicurio_external
# NodePort Service) — must match terraform/{sit,uat,production}/main.tf's
# apicurio_nodeport and devops-engineer/SKILL.md's push-schemas jobs.
$ApicurioNodePort = if ($env:APICURIO_NODEPORT) { $env:APICURIO_NODEPORT } else {
  switch ($ClusterName) {
    'sit' { '30911' }
    'uat' { '30912' }
    'production' { '30913' }
    default { $null }
  }
}

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
  Write-Host "k3d cluster '$ClusterName' already exists - skipping (delete it first if you want to recreate)."
  # ponytail: the running cluster backs storage with $storageVolume. If the
  # volume is gone while the cluster is up, something deleted it and every
  # PVC mount is now broken - say so instead of looking fine.
  docker volume inspect $storageVolume *> $null
  $volExists = $LASTEXITCODE -eq 0
  if (-not $volExists) {
    Write-Host "WARNING: docker volume '$storageVolume' is missing but the cluster is running -"
    Write-Host "         PVC data is likely lost and pods will fail on restart. Recreate:"
    Write-Host "         k3d cluster delete $ClusterName; & '$PSCommandPath' $ClusterName"
  }
  # internal's registry port mapping is edit-able on a running cluster -
  # harmless if it's already there.
  if ($ClusterName -eq 'internal') {
    k3d cluster edit internal --port-add "${RegistryMirrorPort}:${RegistryMirrorPort}@loadbalancer" *> $null
    k3d cluster edit internal --port-add "${MimirPushPort}:${MimirPushPort}@loadbalancer" *> $null
    k3d cluster edit internal --port-add "${LokiPushPort}:${LokiPushPort}@loadbalancer" *> $null
    k3d cluster edit internal --port-add "${TempoPushPort}:${TempoPushPort}@loadbalancer" *> $null
  } elseif ($isPhaseCluster) {
    k3d cluster edit $ClusterName --port-add "${KafkaNodePort}:${KafkaNodePort}@loadbalancer" *> $null
    k3d cluster edit $ClusterName --port-add "${ApicurioNodePort}:${ApicurioNodePort}@loadbalancer" *> $null
  }
  exit 0
}

# Clear a leftover 0-server entry so `k3d cluster create` won't refuse the name.
if (k3d cluster list $ClusterName 2>$null) {
  Write-Host "Removing stale '$ClusterName' entry (0 servers)..."
  k3d cluster delete $ClusterName *> $null
}

docker volume create $storageVolume | Out-Null

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

$extraArgs = @()
$mirrorConfig = $null
if ($ClusterName -eq 'internal') {
  # host ports for the phase clusters' registry mirror + opencost->Mimir bridge.
  $extraArgs += @('-p', "${RegistryMirrorPort}:${RegistryMirrorPort}@loadbalancer")
  $extraArgs += @('-p', "${MimirPushPort}:${MimirPushPort}@loadbalancer")
  $extraArgs += @('-p', "${LokiPushPort}:${LokiPushPort}@loadbalancer")
  $extraArgs += @('-p', "${TempoPushPort}:${TempoPushPort}@loadbalancer")
} elseif ($isPhaseCluster) {
  $mirrorConfig = New-TemporaryFile
  @"
mirrors:
  "harbor.harbor.svc.cluster.local:80":
    endpoint:
      - "http://host.docker.internal:${RegistryMirrorPort}"
"@ | Set-Content -Path $mirrorConfig -Encoding utf8
  $extraArgs += @('--registry-config', $mirrorConfig.FullName)
  # terraform/modules/platform-apps deploys its own traefik (helm/traefik) on
  # phase clusters — k3s's bundled one would fight it for ports 80/443.
  $extraArgs += @('--k3s-arg', '--disable=traefik@server:*')
  # host port for internal's kafka-ui to reach this cluster's kafka.
  $extraArgs += @('-p', "${KafkaNodePort}:${KafkaNodePort}@loadbalancer")
  # host port for internal's GitLab CI to push schemas to this cluster's Apicurio.
  $extraArgs += @('-p', "${ApicurioNodePort}:${ApicurioNodePort}@loadbalancer")
}

# ponytail: docker.sock mount is internal-only — GitLab's docker:dind CI
# runner and omp pods (both internal-only) need the host's docker socket;
# sit/uat/production run neither, mounting it there is pure unused attack
# surface on the k3d node.
$dockerSockArg = @()
if ($ClusterName -eq 'internal') {
  $dockerSockArg = @('--volume', '/var/run/docker.sock:/var/run/docker.sock@server:0')
}

k3d cluster create $ClusterName `
  --volume "${storageVolume}://var/lib/rancher/k3s/storage@server:0" `
  @dockerSockArg `
  @registryArg `
  @extraArgs
if ($LASTEXITCODE -ne 0) { throw "k3d cluster create failed ($LASTEXITCODE)" }
if ($mirrorConfig) { Remove-Item $mirrorConfig -Force }

# ponytail: k3d's managed registry ships with no restart policy, so a Docker
# restart leaves it exited and every image push times out until you notice.
docker update --restart unless-stopped k3d-registry | Out-Null

Write-Host ''
Write-Host "Cluster '$ClusterName' created. PVC data persists in docker volume: $storageVolume"
if ($isPhaseCluster) {
  Write-Host "Registry mirror wired: harbor.harbor.svc.cluster.local:80 -> host.docker.internal:${RegistryMirrorPort}"
  Write-Host "(needs harbor exposed as a NodePort ${RegistryMirrorPort} Service on k3d-internal - separate step)"
  Write-Host "NOTE: this mirror config is baked in at cluster CREATION time - an"
  Write-Host "already-running phase cluster still points at whatever this script said"
  Write-Host "when it was created; recreate it to pick up this change (see AGENT.md)."
} else {
  Write-Host "Next: load .env (copy from .env.example if you haven't), scripts/windows/gen-tfvars.ps1, then (cd terraform/internal; tofu apply)."
}

} finally {
  Pop-Location
}
