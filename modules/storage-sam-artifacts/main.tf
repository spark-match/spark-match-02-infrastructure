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

  bucket_name      = "${var.project_name}-sam-artifacts-${var.environment}"
  access_logs_name = "${local.bucket_name}-access-logs"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "sam_artifacts" {
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

# Deniega explicitamente cualquier request no-TLS (HTTP) al bucket y a sus
# objetos, para todos los principals y acciones. Sin esto, S3 acepta HTTP en
# cleartext ademas de HTTPS. Ref: terraform:S6249 (CWE-319).
resource "aws_s3_bucket_policy" "sam_artifacts_https_only" {
  bucket = aws_s3_bucket.sam_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "SamArtifactsHttpsOnly"
    Statement = [
      {
        Sid       = "HTTPSOnly"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.sam_artifacts.arn,
          "${aws_s3_bucket.sam_artifacts.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
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

###############################################################################
# Access logging: bucket dedicado que recibe los server access logs del
# bucket de artefactos. Ref: terraform:S6258 (CWE-778, insufficient logging).
###############################################################################

resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_144:log bucket, replication innecesaria.
  # checkov:skip=CKV2_AWS_62:log bucket, event notifications innecesarias.
  # checkov:skip=CKV_AWS_18:este ES el bucket de logs; logging sobre si mismo es circular y no aporta valor (excepcion estandar de la industria para buckets destino de access logs).
  bucket        = local.access_logs_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name = local.access_logs_name
  })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (no KMS) en el bucket de logs: el servicio de log delivery de S3
# (logging.s3.amazonaws.com) requiere permisos adicionales sobre la CMK para
# escribir en un destino cifrado con SSE-KMS. AES256 evita esa complejidad
# extra en un bucket que solo contiene logs de acceso (no datos de negocio).
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    expiration {
      days = var.access_logs_retention_days
    }

    filter {}
  }
}

resource "aws_s3_bucket_policy" "access_logs_https_only_and_log_delivery" {
  bucket = aws_s3_bucket.access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "AccessLogsPolicy"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.access_logs.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.sam_artifacts.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "HTTPSOnly"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.access_logs.arn,
          "${aws_s3_bucket.access_logs.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_logging" "sam_artifacts" {
  bucket = aws_s3_bucket.sam_artifacts.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access-logs/"
}
