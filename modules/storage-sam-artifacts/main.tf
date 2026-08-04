###############################################################################
# Module: storage-sam-artifacts
#
# Bucket S3 donde `sam deploy` sube el paquete de despliegue (zip) de
# spark-match-03-backend antes de crear/actualizar el CloudFormation stack.
# Referenciado en 03-backend/samconfig.toml (s3_bucket).
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "storage-sam-artifacts"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  bucket_name = "${var.project_name}-sam-artifacts-${var.environment}"
}

resource "aws_s3_bucket" "sam_artifacts" {
  # checkov:skip=CKV_AWS_18:artifact bucket sin PII/datos de usuario; access logging diferido para POC, no bloqueante para el primer deploy.
  # checkov:skip=CKV_AWS_144:cross-region replication innecesaria para artefactos de build (re-generables via CI en minutos).
  # checkov:skip=CKV2_AWS_62:event notifications innecesarias, no hay consumidor de eventos de este bucket.
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_versioning" "sam_artifacts" {
  bucket = aws_s3_bucket.sam_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sam_artifacts" {
  bucket = aws_s3_bucket.sam_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "sam_artifacts" {
  bucket = aws_s3_bucket.sam_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Housekeeping: los artefactos de builds viejos no tienen valor despues de un
# tiempo (siempre se puede re-generar el zip desde el commit correspondiente
# via CI). Expira versiones no-actuales para no acumular costo de storage.
resource "aws_s3_bucket_lifecycle_configuration" "sam_artifacts" {
  bucket = aws_s3_bucket.sam_artifacts.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    filter {}
  }
}
