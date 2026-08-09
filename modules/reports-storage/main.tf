###############################################################################
# Module: reports-storage
#
# Bucket S3 donde viven los informes de orientacion. El agente
# (spark-match-08-deep-agent) genera el JSON y el PDF y los sube; el backend
# (spark-match-03-backend) guarda en su BD solo la referencia -- bucket, key y
# version_id -- y sirve el contenido por su propia API. Ver ADR-019 de
# 03-backend, decisiones D3 y D11.
#
# SIN CloudFront, a proposito. El valor de CloudFront es cache en el borde y
# aqui no hay nada que cachear: cada informe es privado y lo lee una sola
# persona. Ponerlo delante de contenido privado obligaria ademas a signed URLs
# o signed cookies, o sea key pair en Secrets Manager y su rotacion. Cuidado
# con tomar modules/frontend-hosting como plantilla: ese bucket sirve un sitio
# estatico que lee todo el mundo, el patron de acceso opuesto a este.
#
# El contenido son perfiles vocacionales de estudiantes de secundaria. De ahi
# que aqui no haya ninguna concesion: SSE-KMS con la CMK del proyecto (no
# AES256), los 4 flags de public access block, deny explicito a no-TLS y
# versioning para que un informe emitido no se pueda reescribir en silencio.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "reports-storage"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  bucket_name      = "${var.project_name}-reports-${var.environment}"
  access_logs_name = "${local.bucket_name}-access-logs"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "reports" {
  # checkov:skip=CKV_AWS_144:cross-region replication no habilitada. Un informe perdido se puede volver a generar desde el perfil del estudiante; no justifica el coste de replicacion. Reevaluar si el informe pasa a ser el registro legal de la orientacion.
  # checkov:skip=CKV2_AWS_62:event notifications innecesarias, no hay consumidor de eventos de este bucket.
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

# Versioning es la inmutabilidad del ADR-019 D2: un informe es la foto del
# perfil del estudiante contra una version fechada del dataset, asi que
# reescribirlo destruiria el registro de lo que se le dijo. La BD guarda el
# version_id junto a la key precisamente para poder recuperar la version exacta
# que se le entrego.
resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-KMS con la CMK del proyecto, no AES256. Para datos psicometricos de
# menores interesa que el acceso al texto plano dependa de un permiso de KMS
# auditable y revocable, no solo del permiso de S3.
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    # Reduce las llamadas a KMS reutilizando la data key a nivel de bucket.
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deniega cualquier request no-TLS. Sin esto S3 acepta HTTP en cleartext ademas
# de HTTPS. Ref: terraform:S6249 (CWE-319).
resource "aws_s3_bucket_policy" "reports_https_only" {
  bucket = aws_s3_bucket.reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "ReportsHttpsOnly"
    Statement = [
      {
        Sid       = "HTTPSOnly"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.reports.arn,
          "${aws_s3_bucket.reports.arn}/*",
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

# OJO CON ESTE RECURSO: aqui NO hay regla de expiracion de los informes, y es
# deliberado. El periodo de retencion es lo unico del ADR-019 que sigue sin
# decidirse (ver su seccion 5), y poner un numero por defecto seria decidirlo
# de tapadillo: un `expiration` mal elegido borra informes de estudiantes en
# silencio y sin vuelta atras.
#
# Lo que si se limpia son cosas que no son el informe: subidas multipart que
# quedaron a medias y versiones antiguas de un mismo objeto (que solo aparecen
# si se re-renderiza el PDF sobre la misma key; el informe *nuevo* va a una key
# nueva, asi que esto no toca ningun informe vigente).
resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {}
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    filter {}
  }
}

# El bucket destino de estos logs vive en access-logs.tf, separado a proposito:
# ahi va la supresion de S6258 (un bucket de logs no puede loguearse a si
# mismo) y no debe alcanzar a este fichero, para que la regla siga vigilando
# que el bucket de INFORMES conserve su logging.
resource "aws_s3_bucket_logging" "reports" {
  bucket = aws_s3_bucket.reports.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access-logs/"
}
