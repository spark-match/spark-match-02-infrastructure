#!/bin/bash
# ============================================================================
# plan.sh - terraform plan con salida legible
# ============================================================================
set -euo pipefail

ENV="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

cd "${LIVE_DIR}"

if [ ! -f terraform.tfvars ]; then
  echo "[WARN] terraform.tfvars no existe. Usando variables de ejemplo."
  echo "       Copia terraform.tfvars.example y editalo si necesitas customizar."
fi

echo "=========================================="
echo "  terraform plan (env=${ENV})"
echo "=========================================="
terraform fmt -recursive -diff
terraform init -input=false -upgrade
terraform validate
terraform plan -input=false -out="tfplan" ${@:2}
echo ""
echo "[OK] Plan guardado en tfplan. Para aplicar:"
echo "     ./scripts/apply.sh ${ENV}"