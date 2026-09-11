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
  # complete, not a hang.
  local i types seen="" rc=1 last_beat=0
  for ((i = 0; i < 400; i++)); do
    if ! kubectl -n "$NS" get job "$job" >/dev/null 2>&1; then
      # Job GC'd out from under us (ttl is set high enough this shouldn't
      # normally happen). Trust the last condition we saw; unknown = failure.
      case " $seen " in
        *" Complete "*) echo "${prefix}Job complete (reaped)."; rc=0 ;;
        *) echo "${prefix}Job vanished before completing — kubectl -n $NS get events"; rc=1 ;;
      esac
      break
    fi
    types=$(kubectl -n "$NS" get job "$job" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)
    seen="$types"
    case " $types " in
      *" Complete "*) echo "${prefix}Job complete."
        kubectl -n "$NS" delete job "$job" --ignore-not-found >/dev/null 2>&1 || true
        rc=0; break ;;
      *" Failed "*) echo "${prefix}Job FAILED — kubectl -n $NS describe job/$job"
        rc=1; break ;;
    esac
    if (( i - last_beat >= 40 )); then
      echo "${prefix}...still running ($((i * 3))s)"; last_beat=$i
    fi
    sleep 3
  done
  [ -n "$tail_pid" ] && kill "$tail_pid" 2>/dev/null || true
  if (( i >= 400 )); then
    echo "${prefix}Job timed out after 20m — kubectl -n $NS describe job/$job"
    return 1
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
