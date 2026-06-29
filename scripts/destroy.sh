#!/bin/bash
# ============================================================================
# destroy.sh - terraform destroy (USAR CON CUIDADO)
# ============================================================================
set -euo pipefail

ENV="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

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