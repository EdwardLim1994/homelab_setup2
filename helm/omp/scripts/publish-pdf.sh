#!/bin/sh
# publish-pdf.sh <project> <version> <revision> <markdown-file> [image-file ...]
#
# Converts <markdown-file> to PDF and uploads it to Nextcloud at
# /projects/<project>-<version>-<revision>.pdf, using a throwaway Kubernetes
# Job (this pod's image has pandoc but no PDF engine, deliberately — keeps
# the always-resident image small). Requires nothing but this pod's own
# ServiceAccount token; the sub-Job pulls Nextcloud creds itself via
# secretKeyRef on omp-agent-secrets.
#
# Any trailing image-file arguments (e.g. diagram PNGs from
# render-mermaid.sh) are bundled into the same ConfigMap as binaryData,
# keyed by basename, and land in /input right next to the markdown — so
# markdown's relative `![](diagram.png)` references resolve for pandoc.
set -eu

PROJECT="$1"
VERSION="$2"
REVISION="$3"
MD_FILE="$4"
shift 4
IMAGE_FILES="$*"

TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
API="https://kubernetes.default.svc"
NS=sdlc
ID="pdf-$(date +%s)-$$"

api_curl() {
  curl -sk -H "Authorization: Bearer $TOKEN" "$@"
}

cleanup() {
  api_curl -X DELETE "$API/apis/batch/v1/namespaces/$NS/jobs/$ID?propagationPolicy=Foreground" -o /dev/null || true
  api_curl -X DELETE "$API/api/v1/namespaces/$NS/configmaps/$ID" -o /dev/null || true
}
trap cleanup EXIT

python3 - "$ID" "$NS" "$MD_FILE" $IMAGE_FILES > /tmp/cm.json <<'PY'
import base64, json, os, sys
id_, ns, md_file = sys.argv[1:4]
image_files = sys.argv[4:]
with open(md_file) as f:
    data = f.read()
binary_data = {}
for path in image_files:
    with open(path, "rb") as f:
        binary_data[os.path.basename(path)] = base64.b64encode(f.read()).decode()
print(json.dumps({
    "apiVersion": "v1", "kind": "ConfigMap",
    "metadata": {"name": id_, "namespace": ns},
    "data": {"combined.md": data},
    "binaryData": binary_data,
}))
PY
api_curl -H "Content-Type: application/json" -X POST \
  "$API/api/v1/namespaces/$NS/configmaps" -d @/tmp/cm.json -o /tmp/cm_resp.json -w '%{http_code}\n'

python3 - "$ID" "$NS" "$PROJECT" "$VERSION" "$REVISION" > /tmp/job.json <<'PY'
import json, sys
id_, ns, project, version, revision = sys.argv[1:6]
dest = f"/projects/{project}-{version}-{revision}.pdf"
upload_script = (
    'curl -sf -u "$NEXTCLOUD_USER:$NEXTCLOUD_PASSWORD" -X MKCOL '
    '"$NEXTCLOUD_URL/remote.php/dav/files/$NEXTCLOUD_USER/projects/" || true; '
    'curl -sf -u "$NEXTCLOUD_USER:$NEXTCLOUD_PASSWORD" -T /output/development-plan.pdf '
    f'"$NEXTCLOUD_URL/remote.php/dav/files/$NEXTCLOUD_USER{dest}"'
)
print(json.dumps({
    "apiVersion": "batch/v1", "kind": "Job",
    "metadata": {"name": id_, "namespace": ns},
    "spec": {
        "ttlSecondsAfterFinished": 60,
        "backoffLimit": 0,
        "template": {
            "spec": {
                "restartPolicy": "Never",
                "volumes": [
                    {"name": "input", "configMap": {"name": id_}},
                    {"name": "output", "emptyDir": {}},
                ],
                "initContainers": [{
                    "name": "pandoc",
                    "image": "pandoc/extra:latest",
                    # ponytail: pdflatex (pandoc's default engine) chokes on
                    # non-ASCII (arrows, bullets, checkmarks — agents write
                    # these routinely). xelatex handles Unicode natively.
                    # --resource-path=/input is NOT optional: pandoc resolves
                    # relative image paths (combined.md's `![](diagram.png)`
                    # refs) against its own cwd, not the input file's
                    # directory -- without this every image silently drops
                    # (no error, no non-zero exit, just a text-only PDF,
                    # confirmed via `pdfimages -list` returning zero rows).
                    "command": ["pandoc", "/input/combined.md", "--resource-path=/input", "--pdf-engine=xelatex", "--toc", "--toc-depth=2", "-o", "/output/development-plan.pdf"],
                    "volumeMounts": [
                        {"name": "input", "mountPath": "/input", "readOnly": True},
                        {"name": "output", "mountPath": "/output"},
                    ],
                }],
                "containers": [{
                    "name": "upload",
                    "image": "curlimages/curl:8.10.1",
                    "volumeMounts": [{"name": "output", "mountPath": "/output"}],
                    "env": [
                        {"name": "NEXTCLOUD_URL", "valueFrom": {"secretKeyRef": {"name": "omp-agent-secrets", "key": "nextcloud_url"}}},
                        {"name": "NEXTCLOUD_USER", "valueFrom": {"secretKeyRef": {"name": "omp-agent-secrets", "key": "nextcloud_user"}}},
                        {"name": "NEXTCLOUD_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "omp-agent-secrets", "key": "nextcloud_password"}}},
                    ],
                    "command": ["sh", "-c", upload_script],
                }],
            },
        },
    },
}))
PY
api_curl -H "Content-Type: application/json" -X POST \
  "$API/apis/batch/v1/namespaces/$NS/jobs" -d @/tmp/job.json -o /tmp/job_resp.json -w '%{http_code}\n'

i=0
while [ "$i" -lt 30 ]; do
  sleep 5
  i=$((i + 1))
  STATUS=$(api_curl "$API/apis/batch/v1/namespaces/$NS/jobs/$ID")
  SUCC=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',{}).get('succeeded',0))")
  FAIL=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',{}).get('failed',0))")
  if [ "$SUCC" = "1" ]; then
    echo "PDF published: /projects/${PROJECT}-${VERSION}-${REVISION}.pdf"
    exit 0
  fi
  if [ "$FAIL" != "0" ]; then
    echo "publish-pdf.sh: Job $ID failed" >&2
    POD=$(api_curl "$API/api/v1/namespaces/$NS/pods?labelSelector=job-name=$ID" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['items'][0]['metadata']['name'] if d['items'] else '')")
    if [ -n "$POD" ]; then
      echo "--- pandoc log ---" >&2
      api_curl "$API/api/v1/namespaces/$NS/pods/$POD/log?container=pandoc" >&2
      echo "--- upload log ---" >&2
      api_curl "$API/api/v1/namespaces/$NS/pods/$POD/log?container=upload" >&2
    fi
    exit 1
  fi
done

echo "publish-pdf.sh: Job $ID timed out waiting for completion" >&2
exit 1
