#!/bin/bash
# ============================================================================
# destroy.sh - terraform destroy (USAR CON CUIDADO)
# ============================================================================
# Uso:
#   ./scripts/destroy.sh dev       # destroy dev
#   ./scripts/destroy.sh prod      # destroy prod (doble confirmacion)
#
# El script:
#   1. cd a live/${ENV}
#   2. pide confirmacion textual (escribir 'destroy-${ENV}' literal)
#   3. corre terraform destroy
#
# IMPORTANTE: solo se puede correr manualmente. NO esta expuesto en CI/CD.
# ============================================================================
set -euo pipefail

ENV="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

if [ ! -d "${LIVE_DIR}" ]; then
  echo "[ERROR] Directorio ${LIVE_DIR} no existe."
  exit 1
fi

cd "${LIVE_DIR}"

echo "=========================================="
echo "  ADVERTENCIA: terraform destroy (env=${ENV})"
echo "=========================================="
echo "Esto eliminara TODOS los recursos gestionados por Terraform en ${ENV}."
echo ""

if [ -z "${SKIP_CONFIRM:-}" ]; then
  read -p "Escribe 'destroy-${ENV}' para confirmar: " CONFIRM
  if [ "${CONFIRM}" != "destroy-${ENV}" ]; then
    echo "[CANCEL] Operacion cancelada."
    exit 1
  fi
fi

terraform destroy ${@:2}
