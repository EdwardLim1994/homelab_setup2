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
# pushd/trap so a caller who `source`s this script keeps their own cwd after.
pushd "$(dirname "$0")/../.." >/dev/null
trap 'popd >/dev/null' EXIT

# Harbor's NodePort (harbor Service), host-mapped on k3d-internal's
# loadbalancer. The phase clusters (sit/uat/production) sit on their own
# docker networks and can't reach harbor.harbor.svc.cluster.local
# directly — Docker Desktop's host.docker.internal is reachable from every
# container on every network, so that's the hop. Same port must still be
# wired to the harbor Service as a NodePort (helm/harbor or a one-off
# Service, not this script's job) for any of this to actually resolve.
: "${REGISTRY_MIRROR_PORT:=30500}"

# Same host.docker.internal bridge, for sit/uat/production's opencost to
# remote_write into internal's Mimir (terraform/internal/observability.tf's
# mimir_distributor_nodeport Service is the other half of this bridge).
: "${MIMIR_PUSH_PORT:=30510}"

# Same bridge, for sit/uat/production's log-shipper to push logs into
# internal's Loki (terraform/internal/observability.tf's loki_nodeport
# Service is the other half).
: "${LOKI_PUSH_PORT:=30511}"

# Same bridge, for sit/uat/production's log-shipper to push traces into
# internal's Tempo (terraform/internal/observability.tf's tempo_nodeport
# Service is the other half).
: "${TEMPO_PUSH_PORT:=30512}"

# One argument creates a single named cluster (unchanged, default "internal").
# "phases" creates the 3 phase clusters, each with a containerd mirror config
# so pulls of harbor.harbor.svc.cluster.local/* get redirected
# to host.docker.internal:$REGISTRY_MIRROR_PORT.
if [ "${1:-}" = "phases" ]; then
  for phase in sit uat production; do
    echo "=== $phase ==="
    "$0" "$phase"
  done
  exit 0
fi

# Cluster name: first arg > $K3D_CLUSTER_NAME env > "internal".
K3D_CLUSTER_NAME="${1:-${K3D_CLUSTER_NAME:-internal}}"
# ponytail: named Docker volume, not a host path — one per cluster name so
# separate clusters don't share storage. Override via $K3D_STORAGE_VOLUME.
: "${K3D_STORAGE_VOLUME:=k3d-${K3D_CLUSTER_NAME}-storage}"

case "$K3D_CLUSTER_NAME" in
  sit|uat|production) is_phase_cluster=1 ;;
  *) is_phase_cluster=0 ;;
esac

# host.docker.internal bridge for internal's kafka-ui to reach THIS cluster's
# kafka (terraform/modules/platform-apps/kafka.tf's kafka-external NodePort
# Service). One host port per phase cluster since they share the same Docker
# host — must match terraform/{sit,uat,production}/main.tf's kafka_nodeport
# and helm/kafka-ui/values.yaml's bootstrapServers.
case "$K3D_CLUSTER_NAME" in
  sit) : "${KAFKA_NODEPORT:=30901}" ;;
  uat) : "${KAFKA_NODEPORT:=30902}" ;;
  production) : "${KAFKA_NODEPORT:=30903}" ;;
esac

# Same bridge, for GitLab CI (internal) pushing schemas to THIS cluster's
# Apicurio (terraform/modules/platform-apps/apicurio.tf's apicurio_external
# NodePort Service) — must match terraform/{sit,uat,production}/main.tf's
# apicurio_nodeport and devops-engineer/SKILL.md's push-schemas jobs.
case "$K3D_CLUSTER_NAME" in
  sit) : "${APICURIO_NODEPORT:=30911}" ;;
  uat) : "${APICURIO_NODEPORT:=30912}" ;;
  production) : "${APICURIO_NODEPORT:=30913}" ;;
esac

# ponytail: `k3d cluster list <name>` exits 0 even when only the shared
# k3d-registry node is left (a bare `k3d cluster delete` removes the server
# nodes but keeps the registry, so k3d still lists the name with 0/0
# servers). Check the actual server count, not just presence of the name.
cluster_servers() {
  k3d cluster list "$K3D_CLUSTER_NAME" --no-headers 2>/dev/null \
    | awk '{split($2, s, "/"); print s[2] + 0}'
}

if [ "$(cluster_servers)" -gt 0 ] 2>/dev/null; then
  echo "k3d cluster '$K3D_CLUSTER_NAME' already exists — skipping (delete it first if you want to recreate)."
  # ponytail: the running cluster backs storage with $K3D_STORAGE_VOLUME. If
  # the volume is gone while the cluster is up, something deleted it and
  # every PVC mount is now broken — say so instead of looking fine.
  if ! docker volume inspect "$K3D_STORAGE_VOLUME" &>/dev/null; then
    echo "WARNING: docker volume '$K3D_STORAGE_VOLUME' is missing but the cluster is running —"
    echo "         PVC data is likely lost and pods will fail on restart. Recreate:"
    echo "         k3d cluster delete $K3D_CLUSTER_NAME && $0 $K3D_CLUSTER_NAME"
  fi
  # internal's registry port mapping is edit-able on a running cluster —
  # idempotent-ish (k3d errors harmlessly if it's already there).
  if [ "$K3D_CLUSTER_NAME" = "internal" ]; then
    k3d cluster edit internal --port-add "${REGISTRY_MIRROR_PORT}:${REGISTRY_MIRROR_PORT}@loadbalancer" &>/dev/null || true
    k3d cluster edit internal --port-add "${MIMIR_PUSH_PORT}:${MIMIR_PUSH_PORT}@loadbalancer" &>/dev/null || true
    k3d cluster edit internal --port-add "${LOKI_PUSH_PORT}:${LOKI_PUSH_PORT}@loadbalancer" &>/dev/null || true
    k3d cluster edit internal --port-add "${TEMPO_PUSH_PORT}:${TEMPO_PUSH_PORT}@loadbalancer" &>/dev/null || true
  elif [ "$is_phase_cluster" = "1" ]; then
    k3d cluster edit "$K3D_CLUSTER_NAME" --port-add "${KAFKA_NODEPORT}:${KAFKA_NODEPORT}@loadbalancer" &>/dev/null || true
    k3d cluster edit "$K3D_CLUSTER_NAME" --port-add "${APICURIO_NODEPORT}:${APICURIO_NODEPORT}@loadbalancer" &>/dev/null || true
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

extra_args=()
if [ "$K3D_CLUSTER_NAME" = "internal" ]; then
  # host ports for the phase clusters' registry mirror + opencost->Mimir bridge.
  extra_args+=(-p "${REGISTRY_MIRROR_PORT}:${REGISTRY_MIRROR_PORT}@loadbalancer")
  extra_args+=(-p "${MIMIR_PUSH_PORT}:${MIMIR_PUSH_PORT}@loadbalancer")
  extra_args+=(-p "${LOKI_PUSH_PORT}:${LOKI_PUSH_PORT}@loadbalancer")
  extra_args+=(-p "${TEMPO_PUSH_PORT}:${TEMPO_PUSH_PORT}@loadbalancer")
elif [ "$is_phase_cluster" = "1" ]; then
  # ponytail: NOT mktemp's default /tmp — on Git Bash for Windows that's an
  # MSYS-emulated path the native k3d.exe binary can't open. Repo root (we're
  # already there via pushd) is a real Windows path either way.
  mirror_config="./.registries-mirror-$$.yaml"
  cat > "$mirror_config" <<EOF
mirrors:
  "harbor.harbor.svc.cluster.local:80":
    endpoint:
      - "http://host.docker.internal:${REGISTRY_MIRROR_PORT}"
EOF
  extra_args+=(--registry-config "$mirror_config")
  # terraform/modules/platform-apps deploys its own traefik (helm/traefik) on
  # phase clusters — k3s's bundled one would fight it for ports 80/443.
  extra_args+=(--k3s-arg "--disable=traefik@server:*")
  # host port for internal's kafka-ui to reach this cluster's kafka.
  extra_args+=(-p "${KAFKA_NODEPORT}:${KAFKA_NODEPORT}@loadbalancer")
  # host port for internal's GitLab CI to push schemas to this cluster's Apicurio.
  extra_args+=(-p "${APICURIO_NODEPORT}:${APICURIO_NODEPORT}@loadbalancer")
fi

# ponytail: docker.sock mount is internal-only — GitLab's docker:dind CI
# runner and omp pods (both internal-only) need the host's docker socket;
# sit/uat/production run neither, mounting it there is pure unused attack
# surface on the k3d node.
docker_sock_arg=()
if [ "$K3D_CLUSTER_NAME" = "internal" ]; then
  docker_sock_arg=(--volume "/var/run/docker.sock:/var/run/docker.sock@server:0")
fi

MSYS_NO_PATHCONV=1 k3d cluster create "$K3D_CLUSTER_NAME" \
  --volume "${K3D_STORAGE_VOLUME}://var/lib/rancher/k3s/storage@server:0" \
  "${docker_sock_arg[@]}" \
  "${registry_arg[@]}" \
  "${extra_args[@]}"

[ -n "${mirror_config:-}" ] && rm -f "$mirror_config"

# ponytail: k3d's managed registry ships with no restart policy, so a Docker
# restart leaves it exited and every image push times out until you notice.
docker update --restart unless-stopped k3d-registry >/dev/null

echo
echo "Cluster '$K3D_CLUSTER_NAME' created. PVC data persists in docker volume: $K3D_STORAGE_VOLUME"
if [ "$is_phase_cluster" = "1" ]; then
  echo "Registry mirror wired: harbor.harbor.svc.cluster.local:80 -> host.docker.internal:${REGISTRY_MIRROR_PORT}"
  echo "(needs harbor exposed as a NodePort ${REGISTRY_MIRROR_PORT} Service on k3d-internal — separate step)"
  echo "NOTE: this mirror config is baked in at cluster CREATION time — an"
  echo "already-running phase cluster still points at whatever this script said"
  echo "when it was created; recreate it to pick up this change (see AGENT.md)."
else
  echo "Next: source .env (copy from .env.example if you haven't), scripts/linux/gen-tfvars.sh, then (cd terraform/internal && tofu apply)."
fi
