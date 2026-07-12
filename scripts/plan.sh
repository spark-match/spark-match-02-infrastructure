#!/bin/bash
# ============================================================================
# plan.sh - terraform plan con salida legible
# ============================================================================
# Uso:
#   ./scripts/plan.sh dev        # plan para el entorno dev
#   ./scripts/plan.sh prod       # plan para el entorno prod
#   ./scripts/plan.sh dev -var=foo=bar  # pasa flags adicionales a terraform
#
# El script:
#   1. cd a live/${ENV}
#   2. corre terraform fmt -recursive -diff (auto-fix si hay drift)
#   3. corre terraform init -upgrade (reusa backend si ya esta inicializado)
#   4. corre terraform validate
#   5. corre terraform plan -out=tfplan (auto-loads terraform.tfvars si existe)
#
# El tfplan queda guardado para que apply.sh lo aplique sin re-planear.
# ============================================================================
set -euo pipefail

ENV="${1:-prod}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIVE_DIR="${PROJECT_DIR}/live/${ENV}"

if [ ! -d "${LIVE_DIR}" ]; then
  echo "[ERROR] Directorio ${LIVE_DIR} no existe."
  echo "        Crea live/${ENV}/ con versions.tf, providers.tf, variables.tf, etc."
  exit 1
fi

cd "${LIVE_DIR}"

echo "=========================================="
echo "  terraform plan (env=${ENV})"
echo "=========================================="
echo "  Working dir: ${LIVE_DIR}"

if [ -f terraform.tfvars ]; then
  echo "  Tfvars:      terraform.tfvars (auto-loaded)"
else
  echo "  Tfvars:      (none) usando defaults de variables.tf"
fi

# Auto-fix formatting drift antes de planear (idempotente).
terraform fmt -recursive -diff

terraform init -input=false -upgrade
terraform validate

# terraform auto-loads terraform.tfvars si existe. Pasamos flags adicionales
# que el usuario haya puesto en ${@:2}.
terraform plan -input=false -out="tfplan" ${@:2}
echo ""
echo "[OK] Plan guardado en tfplan. Para aplicar:"
echo "     ./scripts/apply.sh ${ENV}"
