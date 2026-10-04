#!/usr/bin/env bash
# Converts TF_VAR_* lines from root .env into terraform/<env>/local.auto.tfvars,
# one per root module (internal/sit/uat/production). Terraform auto-loads
# *.auto.tfvars, so no flags needed on terraform apply. Run once after editing .env.
#
# ponytail: each env only gets the TF_VAR_* lines it actually declares a
# `variable "<name>"` for - a full copy into every dir would trip the
# "undeclared variable" warning CLAUDE.md already calls out.
set -euo pipefail

# ponytail: absolute paths off the script dir — no cd, so a `source`d call
# leaves the caller's shell where it was.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for env in internal sit uat production; do
  env_dir="$root/terraform/$env"
  [ -d "$env_dir" ] || continue
  declared="$(grep -ohE 'variable\s+"[^"]+"' "$env_dir"/*.tf | sed -E 's/variable\s+"([^"]+)"/\1/')"
  out="$env_dir/local.auto.tfvars"
  : > "$out"
  while IFS= read -r line; do
    name="${line#TF_VAR_}"
    name="${name%%=*}"
    grep -qx "$name" <<<"$declared" || continue
    echo "$name = \"${line#*=}\"" >> "$out"
  done < <(grep "^TF_VAR_" "$root/.env")
  echo "Generated $out ($(wc -l < "$out") vars)"
done
