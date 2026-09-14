#!/usr/bin/env bash
# ponytail: local-path-provisioner (k3s's default StorageClass) stores PVC
# data under /var/lib/rancher/k3s/storage inside the k3d node container.
# k3d normally backs that path with a Docker-managed volume, which survives
# a container restart — but NOT a `k3d cluster delete` (delete removes its
# volumes by design). We back it with a NAMED Docker volume instead (not
# owned by the node's lifecycle, so it survives delete+recreate same as a
# host bind-mount would) — this is what actually happened once already in
# this repo's history (all app data + Authentik's config wiped).
#
# ponytail: was a bind-mount to ./k3d-storage on the Windows host. Docker
# Desktop's Windows<->WSL2 9p filesystem boundary is flaky across host
# sleep/restart — postgres hit "Input/output error" on its data files after
# a Docker Desktop restart, cascading down every app sharing that DB. A
# named Docker volume lives inside the Desktop VM's own disk, no 9p hop.
set -euo pipefail

# ponytail: cd to repo root so a relative K3D_STORAGE_PATH (default or from
# .env) always resolves to ONE place — <repo-root>/k3d-storage — not wherever
# the caller happened to be. Absolute overrides pass through unchanged.
cd "$(dirname "$0")/../.."

# Cluster name: first arg > $K3D_CLUSTER_NAME env > "internal".
K3D_CLUSTER_NAME="${1:-${K3D_CLUSTER_NAME:-internal}}"
# ponytail: named Docker volume, not a host path — one per cluster name so
# separate clusters don't share storage. Override via $K3D_STORAGE_VOLUME.
: "${K3D_STORAGE_VOLUME:=k3d-${K3D_CLUSTER_NAME}-storage}"

# ponytail: `k3d cluster list <name>` exits 0 even when only the shared
# k3d-registry node is left (a bare `k3d cluster delete` removes the server
# nodes but keeps the registry, so k3d still lists the name with 0/0
# servers). Check the actual server count, not just presence of the name.
cluster_servers() {
  k3d cluster list "$K3D_CLUSTER_NAME" --no-headers 2>/dev/null \
    | awk '{split($2, s, "/"); print s[2] + 0}'
}

if [ "$(cluster_servers)" -gt 0 ] 2>/dev/null; then
  echo "k3d cluster '$K3D_CLUSTER_NAME' already exists — use 'k3d cluster start $K3D_CLUSTER_NAME' to resume it, or 'k3d cluster delete $K3D_CLUSTER_NAME' first if you really want to recreate it."
  # ponytail: the running cluster backs storage with $K3D_STORAGE_VOLUME. If
  # the volume is gone while the cluster is up, something deleted it and
  # every PVC mount is now broken — say so instead of looking fine.
  if ! docker volume inspect "$K3D_STORAGE_VOLUME" &>/dev/null; then
    echo "WARNING: docker volume '$K3D_STORAGE_VOLUME' is missing but the cluster is running —"
    echo "         PVC data is likely lost and pods will fail on restart. Recreate:"
    echo "         k3d cluster delete $K3D_CLUSTER_NAME && $0 $K3D_CLUSTER_NAME"
  fi
  exit 0
fi

# Clear a leftover 0-server entry so `k3d cluster create` won't refuse the name.
if k3d cluster list "$K3D_CLUSTER_NAME" &>/dev/null; then
  echo "Removing stale '$K3D_CLUSTER_NAME' entry (0 servers)..."
  k3d cluster delete "$K3D_CLUSTER_NAME" &>/dev/null || true
fi

docker volume create "$K3D_STORAGE_VOLUME" >/dev/null

# ponytail: the shared k3d-registry survives `k3d cluster delete` but stays
# tagged to the deleted cluster — and `k3d cluster create` refuses the name
# while ANY node (registry included) still claims it. Drop the registry when
# it's tied to the target name; reuse it only when another cluster owns it.
reg_cluster="$(k3d registry list --no-headers 2>/dev/null | awk '$1=="k3d-registry"{print $3}')"
if [ -n "$reg_cluster" ] && [ "$reg_cluster" = "$K3D_CLUSTER_NAME" ]; then
  echo "Removing stale registry (tagged to '$K3D_CLUSTER_NAME')..."
  k3d registry delete k3d-registry &>/dev/null || true
  reg_cluster=""
fi

if [ -n "$reg_cluster" ]; then
  registry_arg=(--registry-use "k3d-registry:5111")
else
  registry_arg=(--registry-create "k3d-registry:0.0.0.0:5111")
fi

MSYS_NO_PATHCONV=1 k3d cluster create "$K3D_CLUSTER_NAME" \
  --volume "${K3D_STORAGE_VOLUME}://var/lib/rancher/k3s/storage@server:0" \
  --volume "/var/run/docker.sock:/var/run/docker.sock@server:0" \
  "${registry_arg[@]}"

# ponytail: k3d's managed registry ships with no restart policy, so a Docker
# restart leaves it exited and every image push times out until you notice.
docker update --restart unless-stopped k3d-registry >/dev/null

echo
echo "Cluster '$K3D_CLUSTER_NAME' created. PVC data persists in docker volume: $K3D_STORAGE_VOLUME"
echo "Next: source .env (copy from .env.example if you haven't), then run 'tilt up'."
