#!/usr/bin/env bash
# Restore the shared postgres (authentik/gitlab/litellm/n8n/sonarqube/harbor)
# from a pg_dumpall backup in MinIO (helm/postgres's postgres-backup CronJob,
# bucket postgres-backups, 7-day retention — see terraform/internal/minio.tf).
#
# DESTRUCTIVE: pg_dumpall's plain-SQL output DROPs and recreates every role
# and database it dumped. This overwrites the live DB for every app sharing
# postgres, not just one. Only run this to recover from real data loss.
#
# Usage:
#   scripts/linux/restore-postgres-backup.sh                  # latest backup
#   scripts/linux/restore-postgres-backup.sh <object-name>     # specific one
#   scripts/linux/restore-postgres-backup.sh --list             # list available, don't restore
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && set -a && source "$REPO_ROOT/.env" && set +a

: "${TF_VAR_minio_root_password:?set TF_VAR_minio_root_password in .env}"

mc_run() {
  # ponytail: same kubectl-run-a-throwaway-mc-pod trick used to provision
  # this bucket's lifecycle rule — no mc binary assumed on the host, and
  # this way the request originates inside the cluster network.
  kubectl run "mc-restore-$$-$RANDOM" --rm -i --restart=Never \
    --image=minio/mc:latest --image-pull-policy=IfNotPresent -n minio --command -- \
    sh -c "mc alias set local http://minio.minio.svc.cluster.local:9000 admin '$TF_VAR_minio_root_password' >/dev/null && $1"
}

if [ "${1:-}" = "--list" ]; then
  mc_run "mc ls local/postgres-backups"
  exit 0
fi

if [ -n "${1:-}" ]; then
  OBJECT="$1"
else
  OBJECT="$(mc_run "mc ls local/postgres-backups" | awk '{print $NF}' | sort | tail -1)"
fi

if [ -z "$OBJECT" ]; then
  echo "No backups found in postgres-backups bucket." >&2
  exit 1
fi

echo "WARNING: this will DROP and recreate every role/database in the shared"
echo "postgres from backup object: $OBJECT"
echo "This affects authentik, gitlab, litellm, n8n, sonarqube, harbor — all at once."
read -r -p "Type 'restore' to continue: " confirm
[ "$confirm" = "restore" ] || { echo "Aborted."; exit 1; }

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading $OBJECT from MinIO ..."
kubectl run "mc-restore-dl-$$" --rm -i --restart=Never \
  --image=minio/mc:latest --image-pull-policy=IfNotPresent -n minio --command -- \
  sh -c "mc alias set local http://minio.minio.svc.cluster.local:9000 admin '$TF_VAR_minio_root_password' >/dev/null && mc cat local/postgres-backups/$OBJECT" \
  > "$TMPFILE"

echo "Restoring into postgres-0 ..."
kubectl exec -i -n postgres postgres-0 -- psql -v ON_ERROR_STOP=1 -U postgres -d postgres < "$TMPFILE"

echo "done — restored from $OBJECT. Restart apps that cache DB connections (authentik, gitlab, etc.) if they act stale."
