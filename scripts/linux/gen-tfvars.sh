#!/usr/bin/env bash
# Converts TF_VAR_* lines from root .env into terraform/local.auto.tfvars.
# Terraform auto-loads *.auto.tfvars, so no flags needed on terraform apply.
# Run once after editing .env.
set -euo pipefail
cd "$(dirname "$0")/../.."
grep "^TF_VAR_" .env | sed 's/^TF_VAR_\([^=]*\)=\(.*\)/\1 = "\2"/' > terraform/local.auto.tfvars
echo "Generated terraform/local.auto.tfvars ($(wc -l < terraform/local.auto.tfvars) vars)"
