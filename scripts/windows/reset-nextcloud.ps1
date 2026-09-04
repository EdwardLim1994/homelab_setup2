#!/usr/bin/env pwsh
# PowerShell port of scripts/linux/reset-nextcloud.sh. Needs pwsh 7+, kubectl.
#
# ponytail: if the MariaDB PVC outlives a cluster rebuild while Nextcloud's own
# data PVC is fresh, the entrypoint sees no config.php, retries
# maintenance:install against a DB that still has all the oc_* tables, and aborts
# ("table already exists") - the pod never serves (502). This drops Nextcloud's
# database so the next pod start re-installs it clean.
#
# DESTRUCTIVE: wipes all Nextcloud content. Only run when Nextcloud is already
# broken (crash-looping / 502 with "already exists" in the logs).
# ponytail: NOT 'Stop' - kubectl exec/rollout write to stderr, terminating under
# WinPS 5.1.
$ErrorActionPreference = 'Continue'
$ns = if ($env:NS) { $env:NS } else { 'nextcloud' }

Write-Host "Dropping + recreating the nextcloud database in $ns/nextcloud-mariadb-0 ..."
kubectl exec -n $ns nextcloud-mariadb-0 -- sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS nextcloud; CREATE DATABASE nextcloud;"'

Write-Host 'Restarting Nextcloud ...'
kubectl rollout restart -n $ns deploy/nextcloud
kubectl rollout status  -n $ns deploy/nextcloud --timeout=300s
Write-Host 'done - Nextcloud re-installed its schema.'
