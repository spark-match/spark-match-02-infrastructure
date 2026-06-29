#!/bin/bash
# ============================================================================
# bootstrap-backend.sh
# Crea el bucket S3 y la tabla DynamoDB para almacenar el state remoto de
# Terraform. Se ejecuta UNA SOLA VEZ antes del primer `terraform init`.
# ============================================================================
set -euo pipefail

# --- Configuracion (ajustar si es necesario) ---
PROJECT_NAME="${PROJECT_NAME:-spark-match}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STATE_BUCKET="${PROJECT_NAME}-tfstate-${ENVIRONMENT}"
LOCK_TABLE="${PROJECT_NAME}-tflock"

echo "=========================================="
echo "  Bootstrap Terraform Backend"
echo "  Region:    ${AWS_REGION}"
echo "  Bucket:    ${STATE_BUCKET}"
echo "  Lock table: ${LOCK_TABLE}"
echo "=========================================="

# --- Verificar credenciales ---
if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo "[ERROR] No hay credenciales AWS configuradas."
  echo "        Configura AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY o usa aws configure."
  exit 1
fi

# --- Crear bucket S3 (idempotente) ---
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "[OK] Bucket ${STATE_BUCKET} ya existe."
else
  echo "[INFO] Creando bucket S3 ${STATE_BUCKET}..."
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi

  # Versionado (obligatorio para state)
  aws s3api put-bucket-versioning --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  # Encriptacion server-side
  aws s3api put-bucket-encryption --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

  # Bloqueo de acceso publico
  aws s3api put-public-access-block --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "[OK] Bucket creado con versionado + encriptacion + acceso publico bloqueado."
fi

# --- Crear tabla DynamoDB para lock (idempotente) ---
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${AWS_REGION}" > /dev/null 2>&1; then
  echo "[OK] Tabla DynamoDB ${LOCK_TABLE} ya existe."
else
  echo "[INFO] Creando tabla DynamoDB ${LOCK_TABLE}..."
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" > /dev/null

  echo "[OK] Tabla DynamoDB creada."
fi

echo ""
echo "=========================================="
echo "  Bootstrap completo!"
echo "  Siguiente paso:"
echo "    cd live/prod"
echo "    terraform init -backend-config=\"bucket=${STATE_BUCKET}\" \\"
echo "                    -backend-config=\"key=${ENVIRONMENT}/terraform.tfstate\" \\"
echo "                    -backend-config=\"region=${AWS_REGION}\" \\"
echo "                    -backend-config=\"dynamodb_table=${LOCK_TABLE}\""
echo "=========================================="