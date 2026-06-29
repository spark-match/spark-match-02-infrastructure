# Module: s3-example

Bucket S3 de ejemplo usado como **prueba de concepto** (POC) para verificar que Terraform puede crear recursos en la cuenta AWS.

## Recursos creados

- `aws_s3_bucket` — el bucket en sí
- `aws_s3_bucket_versioning` — versionado habilitado
- `aws_s3_bucket_public_access_block` — bloqueo total de acceso público
- `aws_s3_bucket_server_side_encryption_configuration` — encriptación SSE-S3 (AES256)

## Uso

```hcl
module "s3_example" {
  source = "../../modules/s3-example"

  bucket_name        = "spark-match-poc-ejemplo-12345"
  versioning_enabled = true

  tags = {
    Project     = "spark-match"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
```

## Outputs

| Output | Descripción |
|---|---|
| `bucket_id` | Nombre del bucket |
| `bucket_arn` | ARN completo del bucket |
| `bucket_region` | Región AWS donde se creó |
| `bucket_domain_name` | Dominio del bucket |
| `versioning_enabled` | Estado del versionado (`Enabled`/`Suspended`) |

## Notas

- El nombre del bucket debe ser **globalmente único** en todo AWS (no solo en tu cuenta).
- El bloque de acceso público se aplica por defecto por seguridad.
- Este módulo es solo para POC; el módulo definitivo de storage entrará en Fase 2.