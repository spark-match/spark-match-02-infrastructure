# Runbook — Terraform state recovery

> **Cuando usar este runbook**: si el state file de Terraform se corrompe,
> se borra accidentalmente, o la cuenta AWS pierde acceso al bucket
> `spark-match-tfstate-{dev,prod}`. NO es para recursos individuales que
> fallan — esos van por `terraform plan` + troubleshooting normal.

## Pre-flight: entender el problema

Antes de actuar, identifica:

1. **Ambiente afectado**: dev o prod?
2. **Variable de entorno**: `aws s3 ls s3://spark-match-tfstate-dev` debe
   listar el contenido. Si no, el bucket no existe o las credenciales
   fallan.
3. **Tipo de fallo**:
   - `Error: Failed to read state`: bucket perdido, permisos IAM, o red.
   - `Error: state snapshot ... could not be decoded`: state corrupto.
   - `Error: backend reinitialization required`: el bucket tiene un state
     de otra config.

## Escenario 1 — Bucket entero perdido (worst case)

Si el bucket `spark-match-tfstate-{dev,prod}` fue borrado:

```bash
# 1. Verificar que no existe
aws s3api head-bucket --profile spark-match-admin --bucket spark-match-tfstate-dev
# debe dar: An error occurred (404) when calling the HeadBucket operation: Not Found

# 2. Re-bootstrap (mismo patron que scripts/bootstrap-backend.sh)
aws s3api create-bucket \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev \
  --region us-east-1 \
  --create-bucket-configuration LocationConstraint=us-east-1

aws s3api put-bucket-versioning \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-public-access-block \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**Consecuencia**: el state file se pierde. Habra que re-importar todos los
recursos via `terraform import` o recrearlos desde cero. **Este es el
peor caso — siempre tener backup del state file.**

## Escenario 2 — State file corrupto (versioning recupera)

Si el state file esta corrupto, S3 versioning puede recuperar una version
anterior:

```bash
# 1. Listar versiones del state file
aws s3api list-object-versions \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev \
  --prefix dev/terraform.tfstate \
  --query "Versions[].{Id:VersionId,Date:LastModified}" \
  --output table

# 2. Descargar la version buena (mas reciente que el ultimo apply exitoso)
aws s3api get-object \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  /tmp/terraform.tfstate.recovered

# 3. Validar el JSON
python -c "import json; json.load(open('/tmp/terraform.tfstate.recovered'))"

# 4. Copiar al bucket (esto crea una nueva version)
aws s3 cp /tmp/terraform.tfstate.recovered \
  s3://spark-match-tfstate-dev/dev/terraform.tfstate \
  --profile spark-match-admin

# 5. terraform init + plan para validar
cd live/dev
terraform init
terraform plan
```

## Escenario 3 — Lock huérfano (otro apply dejo lock)

Si el state esta lockeado por otro proceso:

```bash
aws s3api get-object-lock-configuration \
  --profile spark-match-admin \
  --bucket spark-match-tfstate-dev
```

Si Terraform reporto que el lockfile es de un apply de hace >1h, es
probable que el proceso murio. Terraform unlock el lock automaticamente
cuando el proceso termina, pero si el runner de GitHub Actions se cayo
durante un apply, el lock puede quedar.

**Desde Terraform 1.5+**, el backend S3 con `use_lockfile = true` usa
un archivo `.tflock` que se renueva automaticamente y tiene un TTL. Si
el lock es real (no es un caso de carrera), NO lo fuerces — espera al
runner.

## Escenario 4 — Drift no reconciliable (state vs realidad)

Si Terraform reporta recursos que no deberian existir o recursos que
existen pero no estan en el state:

```bash
# Export state para inspect manual
terraform state pull > /tmp/state.json

# Refresh state (re-concilia contra realidad)
terraform apply -refresh-only

# Si un recurso "fantasma" sigue apareciendo, import o remove
terraform import <address> <id>
terraform state rm <address>  # peligroso: deja el recurso huerfano en AWS
```

## Backup preventivo

**Recomendacion**: ejecutar diariamente:

```bash
# Backup del state file de dev
aws s3 cp s3://spark-match-tfstate-dev/dev/terraform.tfstate \
  /backups/spark-match-tfstate-dev-$(date +%Y%m%d).json \
  --profile spark-match-admin

# Backup del state file de prod
aws s3 cp s3://spark-match-tfstate-prod/prod/terraform.tfstate \
  /backups/spark-match-tfstate-prod-$(date +%Y%m%d).json \
  --profile spark-match-admin
```

Esto se puede automatizar con un cron o un workflow semanal. **Sprint 2
lo agrega como `terraform-cleanup.yml` analog pero para backup.**

## Checklist pre-incident

- [ ] Backups del state file en `/backups/spark-match-tfstate-*-{YYYYMMDD}.json` (ultimo 7 dias).
- [ ] Versioning habilitado en `spark-match-tfstate-{dev,prod}` (verificado en este PR).
- [ ] Bloqueo de acceso publico en el bucket (CKV_AWS_53, CKV_AWS_54, CKV_AWS_55, CKV_AWS_56).
- [ ] Encriptacion AES256 habilitada (CKV_AWS_145).
- [ ] Lifecycle policy con `abort_incomplete_multipart_upload_days = 7` (CKV_AWS_300).
- [ ] IAM plan/apply roles tienen acceso al bucket (S3:GetObject, S3:PutObject, S3:ListBucket, S3:GetObjectVersion si versioning).

## References

- `orion-infrastructure/docs/runbook-tfstate-recovery.md` (template).
- `orion-infrastructure/modules/storage-tfstate/main.tf` (patron).
- AWS docs: https://docs.aws.amazon.com/whitepapers/latest/aws-storage-services-overview/terraform-state-storage.html
- Terraform docs: https://developer.hashicorp.com/terraform/language/state/backends/s3
