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

: "${K3D_CLUSTER_NAME:=internal-dev}"
: "${K3D_STORAGE_PATH:=./k3d-storage}"

if k3d cluster list "$K3D_CLUSTER_NAME" &>/dev/null; then
  echo "k3d cluster '$K3D_CLUSTER_NAME' already exists — use 'k3d cluster start $K3D_CLUSTER_NAME' to resume it, or 'k3d cluster delete $K3D_CLUSTER_NAME' first if you really want to recreate it."
  exit 0
fi

mkdir -p "$K3D_STORAGE_PATH"
storage_path_abs="$(cd "$K3D_STORAGE_PATH" && pwd)"

MSYS_NO_PATHCONV=1 k3d cluster create "$K3D_CLUSTER_NAME" \
  --volume "${storage_path_abs}://var/lib/rancher/k3s/storage@server:0"

echo
echo "Cluster '$K3D_CLUSTER_NAME' created. PVC data persists at: $storage_path_abs"
echo "Next: source .env (copy from .env.example if you haven't), then run 'tilt up'."
