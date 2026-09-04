#!/usr/bin/env bash
# ponytail: if the MariaDB PVC outlives a cluster rebuild while Nextcloud's own
# data PVC is fresh, the entrypoint sees no config.php, retries maintenance:install
# against a DB that still has all the oc_* tables, and aborts ("table already
# exists") — the pod never serves (502).
# This drops Nextcloud's database so the next pod start re-installs it clean.
#
# DESTRUCTIVE: wipes all Nextcloud content. Only run when Nextcloud is already
# broken (crash-looping / 502 with "already exists" in the logs).
set -euo pipefail
: "${NS:=nextcloud}"

echo "Dropping + recreating the nextcloud database in $NS/nextcloud-mariadb-0 ..."
kubectl exec -n "$NS" nextcloud-mariadb-0 -- sh -c '
  mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "
    DROP DATABASE IF EXISTS nextcloud;
    CREATE DATABASE nextcloud;"'

echo "Restarting Nextcloud ..."
kubectl rollout restart -n "$NS" deploy/nextcloud
kubectl rollout status  -n "$NS" deploy/nextcloud --timeout=300s
echo "done — Nextcloud re-installed its schema."
