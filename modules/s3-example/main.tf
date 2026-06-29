###############################################################################
# Module: s3-example
# Prueba de concepto: bucket S3 simple como demo de Terraform + AWS.
###############################################################################

resource "aws_s3_bucket" "this" {
  # El nombre del bucket debe ser globalmente unico en AWS.
  # Usamos el prefijo del proyecto + nombre configurable.
  bucket = var.bucket_name

  # Los tags se aplican via el bloque "tags" en lugar de "bucket" para
  # mantener compatibilidad con providers antiguos (en 5.40 ya se puede
  # usar el recurso aws_s3_bucket_tagging por separado).
  tags = merge(
    var.tags,
    {
      Purpose = "terraform-aws-poc"
    },
  )
}

# Versionado del bucket (recomendado para buckets con datos importantes)
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Bloquear acceso publico (best practice para buckets privados)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encriptacion server-side por defecto (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}