#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# setup-aws-secrets.sh
# =============================================================================
# Idempotent setup of the 4 AWS secrets consumed by the 4 terraform-{plan,
# apply}-{dev,prod}.yml callers in spark-match-02-infrastructure. Each secret
# is set at the GH Environment that matches the env the secret name is
# suffixed with. Caller convention (unchanged in this PR):
#
#   plan-dev.yml   uses plan-role-arn-secret:  AWS_PLAN_ROLE_ARN_DEV
#   plan-prod.yml  uses plan-role-arn-secret:  AWS_PLAN_ROLE_ARN_PROD
#   apply-dev.yml  uses apply-role-arn-secret: AWS_APPLY_ROLE_ARN_DEV
#   apply-prod.yml uses apply-role-arn-secret: AWS_APPLY_ROLE_ARN_PROD
#
# Flags (all optional):
#   --repo OWNER/REPO       Default: spark-match/spark-match-02-infrastructure
#   --aws-account ID        Default: 681526276858
#   --env-dev NAME          Default: dev
#   --env-prod NAME         Default: production
#   --role-suffix-dev       Default: -dev
#   --role-suffix-prod      Default: -prod
#   --dry-run               Print gh secret set commands without applying
#   --check                 Verify all 4 secrets exist; exit 1 if any missing
#
# Exit codes: 0 success, 1 missing (only in --check), 2 gh not authed, 3 invalid flag
# =============================================================================

REPO="spark-match/spark-match-02-infrastructure"
AWS_ACCOUNT="681526276858"
ENV_DEV="dev"
ENV_PROD="production"
SUFFIX_DEV="-dev"
SUFFIX_PROD="-prod"
DRY_RUN="false"
CHECK_ONLY="false"

usage() {
  sed -n '2,30p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)                REPO="$2"; shift 2 ;;
    --aws-account)         AWS_ACCOUNT="$2"; shift 2 ;;
    --env-dev)             ENV_DEV="$2"; shift 2 ;;
    --env-prod)            ENV_PROD="$2"; shift 2 ;;
    --role-suffix-dev)     SUFFIX_DEV="$2"; shift 2 ;;
    --role-suffix-prod)    SUFFIX_PROD="$2"; shift 2 ;;
    --dry-run)             DRY_RUN="true"; shift ;;
    --check)               CHECK_ONLY="true"; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     echo "::error::Unknown flag: $1" >&2; usage; exit 3 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "::error::gh CLI not found" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "::error::gh not authenticated" >&2; exit 2; }

PLAN_ARN_DEV="arn:aws:iam::${AWS_ACCOUNT}:role/spark-match-terraform-plan${SUFFIX_DEV}"
PLAN_ARN_PROD="arn:aws:iam::${AWS_ACCOUNT}:role/spark-match-terraform-plan${SUFFIX_PROD}"
APPLY_ARN_DEV="arn:aws:iam::${AWS_ACCOUNT}:role/spark-match-terraform-apply${SUFFIX_DEV}"
APPLY_ARN_PROD="arn:aws:iam::${AWS_ACCOUNT}:role/spark-match-terraform-apply${SUFFIX_PROD}"

declare -a TARGETS=(
  "${ENV_DEV} AWS_PLAN_ROLE_ARN_DEV ${PLAN_ARN_DEV}"
  "${ENV_DEV} AWS_APPLY_ROLE_ARN_DEV ${APPLY_ARN_DEV}"
  "${ENV_PROD} AWS_PLAN_ROLE_ARN_PROD ${PLAN_ARN_PROD}"
  "${ENV_PROD} AWS_APPLY_ROLE_ARN_PROD ${APPLY_ARN_PROD}"
)

set_secret() {
  local env="$1" name="$2" value="$3"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] gh secret set \"${name}\" --repo \"${REPO}\" --env \"${env}\" --body \"${value}\""
    return 0
  fi
  echo "$value" | gh secret set "$name" --repo "$REPO" --env "$env" --body - >/dev/null
  echo "[ok] ${env} :: ${name} (value masked, length=${#value})"
}

check_secret() {
  local env="$1" name="$2"
  if gh secret list --repo "$REPO" --env "$env" 2>/dev/null | grep -q "^${name}\b"; then
    echo "[ok] ${env} :: ${name} present"
    return 0
  fi
  echo "[missing] ${env} :: ${name}"
  return 1
}

if [[ "${CHECK_ONLY}" == "true" ]]; then
  echo "Checking 4 secrets in repo ${REPO}..."
  missing=0
  for entry in "${TARGETS[@]}"; do
    read -r env name value <<<"$entry"
    if ! check_secret "$env" "$name"; then
      missing=$((missing + 1))
    fi
  done
  if [[ $missing -gt 0 ]]; then
    echo "::error::${missing} secret(s) missing. Run without --check to create them."
    exit 1
  fi
  echo "All 4 secrets present."
  exit 0
fi

echo "Setting 4 secrets in repo ${REPO} (aws account ${AWS_ACCOUNT})..."
for entry in "${TARGETS[@]}"; do
  read -r env name value <<<"$entry"
  set_secret "$env" "$name" "$value"
done
echo "Done. Verify with: $0 --check"
