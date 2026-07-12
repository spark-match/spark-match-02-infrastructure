#!/bin/bash
# ============================================================================
# apply.sh - terraform apply desde un plan pre-aprobado
# ============================================================================
# Uso:
#   ./scripts/apply.sh dev        # apply para dev
#   ./scripts/apply.sh prod       # apply para prod
#
# El script:
#   1. cd a live/${ENV}
#   2. verifica que tfplan existe (generado por plan.sh)
#   3. pide confirmacion explicita (salvo si TF_VAR_auto_approve=true)
#   4. corre terraform apply tfplan
#   5. borra tfplan (limpieza post-apply)
#
# NOTA: en CI/CD se usa con TF_VAR_auto_approve=true (los reusables de GH Actions
# invocan terraform apply directo, no este script). Este script es para uso
# local del operador.
# ============================================================================
set -euo pipefail

# Argumento obligatorio: <dev|prod>. Sin argumento o argumento invalido falla rapido.
ENV="${1:?Uso: $0 <dev|prod>}"
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "[ERROR] Ambiente invalido: '${ENV}'. Valores permitidos: dev, prod." >&2
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

if [ ! -d "${LIVE_DIR}" ]; then
  echo "[ERROR] Directorio ${LIVE_DIR} no existe."
  exit 1
fi

cd "${LIVE_DIR}"

if [ ! -f tfplan ]; then
  echo "[ERROR] No existe tfplan. Ejecuta primero: ./scripts/plan.sh ${ENV}"
  exit 1
fi

echo "=========================================="
echo "  terraform apply (env=${ENV})"
echo "=========================================="
echo "  Working dir: ${LIVE_DIR}"

if [ -z "${TF_VAR_auto_approve:-}" ]; then
  read -p "Estas seguro de aplicar este plan en ${ENV}? (yes/no): " CONFIRM
  if [ "${CONFIRM}" != "yes" ]; then
    echo "[CANCEL] Operacion cancelada por el usuario."
    exit 1
  fi
fi

terraform apply -input=false tfplan
rm -f tfplan
echo ""
echo "[OK] Apply completo en ${ENV}."
