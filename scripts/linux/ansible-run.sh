#!/usr/bin/env bash
# Trigger one-shot ansible runs in-cluster, stream logs, let k8s reap the pods.
#
# ponytail: the "ansible server" is a permanently-suspended CronJob
# (helm/ansible). This clones a Job from it — no idle pod, no shutdown logic,
# the Job's ttlSecondsAfterFinished deletes the pod when it's done.
#
#   scripts/linux/ansible-run.sh                    # ALL playbooks, in parallel
#   scripts/linux/ansible-run.sh n8n                # runs playbooks/n8n.yml
#   scripts/linux/ansible-run.sh n8n --syntax-check # parse-only (self-check)
#
# ponytail: no-arg fans out one Job per playbook instead of the serial
# site.yml. Independent playbooks (own namespace each) run concurrently.
# Pass a playbook name explicitly (or `site`) to run just that one.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/linux/ansible-run.sh [playbook] [ansible-args...]
       scripts/linux/ansible-run.sh --help | -h

Clones a one-shot Job from the suspended ansible-runner CronJob (helm/ansible),
streams its logs, lets k8s reap the pod when done.

With no argument: runs every playbook in the default fan-out, in parallel.
Pass "site" to run the same set serially instead. Pass a playbook name to
run just that one (including bootstrap/DR-only ones, never run by default).

Common ansible-args: --syntax-check (parse-only, no changes), --tags <tag>,
-e key=value (extra vars).

DEFAULT FAN-OUT (no arg runs all of these, in parallel):
  n8n                   n8n post-deploy: owner setup, mint/reuse API key, seed the SDLC flows
  omp                   Push a GitLab token into every omp pod's env
  litellm               Wait for the LiteLLM proxy, confirm models loaded
  mcp-servers           Push access tokens from .env into each MCP server Deployment
  openwebui             Install the SDLC pipe as an OpenWebUI Function (idempotent)

  site                  Run the exact same set SERIALLY instead of in parallel

BOOTSTRAP / DISASTER-RECOVERY (not in the default fan-out — run explicitly):
  gitlab-webhook        Register/verify/deregister the n8n SDLC router webhook (F-00) on
                        every sdlc-group project (--tags verify | --tags deregister
                        -e deregister_confirmed=true)
  sonarqube-gitlab      Configure SonarQube's GitLab DevOps Platform Integration
  argocd-clusters       Register the phase k3d clusters (sit/uat/qa/staging/production) with ArgoCD
  role-accounts         Create one GitLab + Kaneo service account per SDLC role
                        (idempotent, re-run-safe — see AGENTS.md's "Ticket assignee")

Examples:
  scripts/linux/ansible-run.sh
  scripts/linux/ansible-run.sh n8n
  scripts/linux/ansible-run.sh n8n --syntax-check
  scripts/linux/ansible-run.sh gitlab-webhook --tags verify
  scripts/linux/ansible-run.sh role-accounts
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

: "${NS:=ansible}"
: "${CRONJOB:=ansible-runner}"

# Playbooks with no cross-dependencies — safe to run at the same time.
PARALLEL_PLAYBOOKS=(n8n omp litellm mcp-servers openwebui)
# Ordered chains: each chain runs serially, chains run concurrently with each
# other and with PARALLEL_PLAYBOOKS. Empty now that mattermost (the only
# chained-after-n8n playbook) is gone — n8n runs standalone.
CHAINS=()

# run_playbook <playbook> [ansible args...]
# Creates the Job, streams its logs (prefixed when running in parallel),
# waits for completion. Returns non-zero if the Job fails.
run_playbook() {
  local pb="$1"; shift
  local args="$*"
  local job="ansible-${pb}-$(date +%s)-${RANDOM}"
  local prefix=""
  [ "${PARALLEL:-0}" = "1" ] && prefix="[${pb}] "

  # ponytail: `kubectl set env --local` rewrites env in the rendered manifest
  # offline — no jq, no post-create race.
  kubectl -n "$NS" create job "$job" --from="cronjob/${CRONJOB}" --dry-run=client -o yaml \
    | kubectl set env --local -f - -o yaml \
        "PLAYBOOK=${pb}.yml" "ANSIBLE_ARGS=${args}" \
    | kubectl apply -f - >/dev/null

  echo "${prefix}Job $job created — waiting for pod..."

  # ponytail: `kubectl logs -f` can block forever (pod stuck ContainerCreating,
  # backoffLimit retry, TTL reap mid-stream). Run it in the background as a
  # best-effort tail and let the status poll below be the authority on done.
  local pod=""
  local j
  for ((j = 0; j < 60; j++)); do
    pod=$(kubectl -n "$NS" get pod -l "job-name=$job" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [ -n "$pod" ] && break
    sleep 2
  done
  local tail_pid=""
  if [ -n "$pod" ]; then
    ( kubectl -n "$NS" logs -f "$pod" 2>/dev/null | sed "s/^/${prefix}/" ) &
    tail_pid=$!
  fi

  # ponytail: poll the job's terminal condition. `kubectl wait
  # --for=condition=complete` blocks the full --timeout on a Failed job, and a
  # job that TTL-reaps after succeeding disappears entirely — treat "gone" as
  # complete, not a hang. A single failed `kubectl get job` is frequently just
  # a transient API-server blip (TLS handshake timeout, brief network flake),
  # NOT proof the job vanished — require 3 CONSECUTIVE failures before
  # concluding that, and track every blip so the final RESULT line can flag
  # "succeeded, but polling was flaky" instead of silently hiding it.
  local i types seen="" rc=1 last_beat=0 gone_streak=0 blips=0
  for ((i = 0; i < 400; i++)); do
    if ! kubectl -n "$NS" get job "$job" >/dev/null 2>&1; then
      gone_streak=$((gone_streak + 1)); blips=$((blips + 1))
      if (( gone_streak < 3 )); then
        sleep 2
        continue
      fi
      case " $seen " in
        *" Complete "*) rc=0 ;;
        *) rc=1 ;;
      esac
      break
    fi
    gone_streak=0
    types=$(kubectl -n "$NS" get job "$job" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)
    [ -z "$types" ] && blips=$((blips + 1))
    seen="$types"
    case " $types " in
      *" Complete "*)
        kubectl -n "$NS" delete job "$job" --ignore-not-found >/dev/null 2>&1 || true
        rc=0; break ;;
      *" Failed "*) rc=1; break ;;
    esac
    if (( i - last_beat >= 40 )); then
      echo "${prefix}...still running ($((i * 3))s)"; last_beat=$i
    fi
    sleep 3
  done
  [ -n "$tail_pid" ] && kill "$tail_pid" 2>/dev/null || true

  if (( i >= 400 )); then
    echo "${prefix}RESULT: FAILED — timed out after 20m — kubectl -n $NS describe job/$job"
    return 1
  fi
  if (( rc == 0 )); then
    if (( blips > 0 )); then
      echo "${prefix}RESULT: WARNING — job Complete, but $blips transient kubectl API blip(s) occurred while polling (not a real failure; verify yourself if unsure: kubectl -n $NS get job $job -o yaml)"
    else
      echo "${prefix}RESULT: SUCCESS — job Complete"
    fi
  else
    if (( gone_streak >= 3 )); then
      echo "${prefix}RESULT: FAILED — job genuinely vanished (confirmed gone across 3 consecutive checks, last seen condition: '${seen:-none}') — kubectl -n $NS get events"
    else
      echo "${prefix}RESULT: FAILED — job condition Failed — kubectl -n $NS describe job/$job"
    fi
  fi
  return $rc
}

# run_chain "<pb1> <pb2> ..." [ansible args...] — stop on first failure.
run_chain() {
  local chain="$1"; shift
  local pb
  for pb in $chain; do
    run_playbook "$pb" "$@" || return 1
  done
}

# --- single playbook: explicit arg (or `site`) -------------------------------
if [ "${1:-}" != "" ]; then
  PB="$1"; shift || true
  run_playbook "$PB" "$@"
  exit $?
fi

# --- no arg: run everything, in parallel ------------------------------------
export PARALLEL=1
declare -a PIDS=() LABELS=()

for pb in "${PARALLEL_PLAYBOOKS[@]}"; do
  run_playbook "$pb" "$@" & PIDS+=($!); LABELS+=("$pb")
done
for chain in "${CHAINS[@]}"; do
  run_chain "$chain" "$@" & PIDS+=($!); LABELS+=("chain: $chain")
done

FAILED=()
for i in "${!PIDS[@]}"; do
  wait "${PIDS[$i]}" || FAILED+=("${LABELS[$i]}")
done

if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "All playbooks complete."
else
  printf 'FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi
