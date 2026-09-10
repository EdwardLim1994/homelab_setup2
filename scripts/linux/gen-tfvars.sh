#!/usr/bin/env bash
# Converts TF_VAR_* lines from root .env into terraform/local.auto.tfvars.
# Terraform auto-loads *.auto.tfvars, so no flags needed on terraform apply.
# Run once after editing .env.
set -euo pipefail

# ponytail: absolute paths off the script dir — no cd, so a `source`d call
# leaves the caller's shell where it was.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
grep "^TF_VAR_" "$root/.env" \
  | sed 's/^TF_VAR_\([^=]*\)=\(.*\)/\1 = "\2"/' > "$root/terraform/local.auto.tfvars"
echo "Generated terraform/local.auto.tfvars ($(wc -l < "$root/terraform/local.auto.tfvars") vars)"
