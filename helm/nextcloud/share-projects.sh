#!/bin/bash
# ponytail: no-op until ADMIN_EMAIL has logged in via SSO once (same
# JIT-account reasoning as promote-admin.sh) — safe to run on every terraform
# reload. publish-pdf.sh (plan_release's PM compile step) uploads via WebDAV
# as the built-in `admin` user — that's a private folder invisible to
# anyone else's account, SSO-promoted-to-admin-group or not (group
# membership doesn't grant access to another user's personal files). Share
# admin's /projects folder with ADMIN_EMAIL's own SSO account so the
# published reports/PDFs are actually visible to a human.
set -e
OCC="runuser -u www-data -- php /var/www/html/occ"
uid=$($OCC user:list --info --output=json | php -r '
  $j = json_decode(stream_get_contents(STDIN), true) ?: [];
  foreach ($j as $u => $i) {
    if (($i["email"] ?? "") === getenv("ADMIN_EMAIL")) { echo $u; exit; }
  }')
if [ -z "$uid" ]; then
  echo "nextcloud share skipped: no user yet for ${ADMIN_EMAIL} (log in via SSO first)"
  exit 0
fi

# permissions bitmask: 1=read, 8=delete -> 9=read+delete. User can view and
# remove published proposal PDFs but not edit/reshare admin's folder.
share_id=$(curl -sf -u "admin:${NEXTCLOUD_ADMIN_PASSWORD}" -H "OCS-APIRequest: true" \
  "http://localhost/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" \
  | SHARE_UID="$uid" php -r '
    $j = json_decode(stream_get_contents(STDIN), true) ?: [];
    foreach (($j["ocs"]["data"] ?? []) as $s) {
      if (($s["path"] ?? "") === "/projects" && ($s["share_with"] ?? "") === getenv("SHARE_UID")) { echo $s["id"] . "," . $s["permissions"]; exit; }
    }')

if [ -n "$share_id" ]; then
  id="${share_id%%,*}"
  perms="${share_id##*,}"
  if [ "$perms" = "9" ]; then
    echo "nextcloud share ready: /projects already shared with $uid (read+delete)"
    exit 0
  fi
  # ponytail: permissions set before the delete-bit fix — update in place
  # rather than deleting+recreating the share, keeps the same share id stable.
  curl -sf -u "admin:${NEXTCLOUD_ADMIN_PASSWORD}" -H "OCS-APIRequest: true" \
    -X PUT "http://localhost/ocs/v2.php/apps/files_sharing/api/v1/shares/$id?format=json" \
    --data-urlencode "permissions=9" > /dev/null
  echo "nextcloud share updated: /projects -> $uid now read+delete"
  exit 0
fi

curl -sf -u "admin:${NEXTCLOUD_ADMIN_PASSWORD}" -H "OCS-APIRequest: true" \
  -X POST "http://localhost/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json" \
  --data-urlencode "path=projects" \
  --data-urlencode "shareType=0" \
  --data-urlencode "shareWith=$uid" \
  --data-urlencode "permissions=9" > /dev/null
echo "nextcloud share created: /projects -> $uid (read+delete)"
