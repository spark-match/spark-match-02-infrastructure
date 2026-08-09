###############################################################################
# Bucket destino de los server access logs del bucket de informes.
#
# VIVE EN SU PROPIO FICHERO A PROPOSITO. Sonar marca S6258 ("disabling logging")
# sobre este bucket, porque no tiene access logging propio -- activarselo seria
# circular, sus logs generarian logs. Es la excepcion estandar para buckets
# destino de access logs.
#
# La supresion de esa regla (sonar-project.properties, criterio e3) solo puede
# apuntar a un fichero completo, no a un recurso. Si estos recursos vivieran en
# main.tf, esa supresion taparia tambien el dia que alguien borrase
# `aws_s3_bucket_logging.reports` y dejase el bucket de INFORMES sin registro de
# accesos -- justo lo que la regla existe para evitar. Separandolos, main.tf
# sigue vigilado por S6258 y aqui la excepcion esta acotada a donde es legitima.
#
# Sobre datos personales de menores estos logs son el registro de quien leyo que
# informe y cuando, asi que su retencion (365 dias por defecto) no deberia
# bajarse sin pensarlo.
###############################################################################

resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_145:log bucket cifrado con SSE-S3 (AES256). SSE-KMS exigiria dar permisos sobre la CMK al servicio de entrega de logs (logging.s3.amazonaws.com). Mismo criterio que modules/storage-sam-artifacts y modules/frontend-hosting.
  # checkov:skip=CKV_AWS_21:versioning no habilitado en un log bucket. Cada entrada generaria una version y los logs son append-only.
  # checkov:skip=CKV_AWS_144:log bucket, replication innecesaria.
  # checkov:skip=CKV2_AWS_62:log bucket, event notifications innecesarias.
  # checkov:skip=CKV_AWS_18:este ES el bucket de logs; logging sobre si mismo es circular.
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

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  # checkov:skip=CKV_AWS_300:abort_incomplete_multipart_upload no aplica a un bucket destino de access logs (los escribe el propio servicio de S3, sin multipart).
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
    Id      = "ReportsAccessLogsPolicy"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.access_logs.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.reports.arn
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
