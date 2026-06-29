#!/bin/bash
# ============================================================================
# apply.sh - terraform apply desde un plan pre-aprobado
# ============================================================================
set -euo pipefail

ENV="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

cd "${LIVE_DIR}"

if [ ! -f tfplan ]; then
  echo "[ERROR] No existe tfplan. Ejecuta primero: ./scripts/plan.sh ${ENV}"
  exit 1
fi

echo "=========================================="
echo "  terraform apply (env=${ENV})"
echo "=========================================="

if [ -z "${TF_VAR_auto_approve:-}" ]; then
  read -p "Estas seguro de aplicar este plan? (yes/no): " CONFIRM
  if [ "${CONFIRM}" != "yes" ]; then
    echo "[CANCEL] Operacion cancelada por el usuario."
    exit 1
  fi
fi

terraform apply -input=false tfplan
rm -f tfplan
echo ""
echo "[OK] Apply completo."