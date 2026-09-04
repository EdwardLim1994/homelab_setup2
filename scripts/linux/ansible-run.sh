#!/usr/bin/env bash
# Trigger a one-shot ansible run in-cluster, stream its logs, let k8s reap it.
#
# ponytail: the "ansible server" is a permanently-suspended CronJob
# (helm/ansible). This clones a Job from it — no idle pod, no shutdown logic,
# the Job's ttlSecondsAfterFinished deletes the pod when it's done.
#
#   scripts/linux/ansible-run.sh                    # runs playbooks/site.yml
#   scripts/linux/ansible-run.sh n8n                # runs playbooks/n8n.yml
#   scripts/linux/ansible-run.sh n8n --syntax-check # parse-only (self-check)
set -euo pipefail

: "${NS:=ansible}"
: "${CRONJOB:=ansible-runner}"

PB="${1:-site}"
shift || true
ARGS="$*"
JOB="ansible-${PB}-$(date +%s)"

# ponytail: `kubectl set env --local` rewrites the env in the rendered manifest
# offline — no jq, no post-create race.
kubectl -n "$NS" create job "$JOB" --from="cronjob/${CRONJOB}" --dry-run=client -o yaml \
  | kubectl set env --local -f - -o yaml \
      "PLAYBOOK=${PB}.yml" "ANSIBLE_ARGS=${ARGS}" \
  | kubectl apply -f -

cleanup() { kubectl -n "$NS" delete job "$JOB" --ignore-not-found >/dev/null 2>&1 || true; }

echo "Job $JOB created — waiting for pod..."
kubectl -n "$NS" wait --for=condition=ready pod -l "job-name=$JOB" --timeout=120s 2>/dev/null || true
kubectl -n "$NS" logs -f "job/$JOB" 2>/dev/null || true

if kubectl -n "$NS" wait --for=condition=complete "job/$JOB" --timeout=600s 2>/dev/null; then
  echo "Job complete."
  cleanup
else
  echo "Job FAILED — inspect with: kubectl -n $NS describe job/$JOB"
  exit 1
fi
