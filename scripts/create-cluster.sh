#!/usr/bin/env bash
# ponytail: local-path-provisioner (k3s's default StorageClass) stores PVC
# data under /var/lib/rancher/k3s/storage inside the k3d node container.
# k3d normally backs that path with a Docker-managed volume, which survives
# a container restart — but NOT a `k3d cluster delete` (delete removes its
# volumes by design). Bind-mounting a real host directory to that path
# means PVC data survives even a deliberate cluster delete+recreate, not
# just a container restart. This is what actually happened once already in
# this repo's history (all app data + Authentik's config wiped).
set -euo pipefail

# ponytail: default storage path is repo-root-relative — run from anywhere.
cd "$(dirname "$0")/.."

: "${K3D_CLUSTER_NAME:=internal-dev}"
: "${K3D_STORAGE_PATH:=./k3d-storage}"

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
  exit 0
fi

# Clear a leftover 0-server entry so `k3d cluster create` won't refuse the name.
if k3d cluster list "$K3D_CLUSTER_NAME" &>/dev/null; then
  echo "Removing stale '$K3D_CLUSTER_NAME' entry (0 servers)..."
  k3d cluster delete "$K3D_CLUSTER_NAME" &>/dev/null || true
fi

mkdir -p "$K3D_STORAGE_PATH"
storage_path_abs="$(cd "$K3D_STORAGE_PATH" && pwd)"

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
  --volume "${storage_path_abs}://var/lib/rancher/k3s/storage@server:0" \
  --volume "/var/run/docker.sock:/var/run/docker.sock@server:0" \
  "${registry_arg[@]}"

# ponytail: k3d's managed registry ships with no restart policy, so a Docker
# restart leaves it exited and every image push times out until you notice.
docker update --restart unless-stopped k3d-registry >/dev/null

echo
echo "Cluster '$K3D_CLUSTER_NAME' created. PVC data persists at: $storage_path_abs"
echo "Next: source .env (copy from .env.example if you haven't), then run 'tilt up'."
