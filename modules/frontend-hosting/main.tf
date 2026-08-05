locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "frontend-hosting"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  bucket_name      = "${var.bucket_name_prefix}-${var.environment}"
  access_logs_name = "${local.bucket_name}-access-logs"
  log_prefix       = "cloudfront-access-logs/"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "frontend" {
  # checkov:skip=CKV_AWS_144:cross-region replication innecesaria para assets de build estatico (re-generables via CI en minutos).
  # checkov:skip=CKV_AWS_145:por default SSE-S3 (AES256). SSE-KMS opt-in via enable_kms_encryption=true para no obligar a cifrar con la CMK del proyecto un bucket de assets publicos servidos por CloudFront.
  # checkov:skip=CKV_AWS_18:logging configurado via aws_s3_bucket_logging hacia el bucket access-logs dedicado (definido mas abajo). Checkov no lo detecta como logging "valido" porque el target_bucket es creado por el mismo modulo.
  # checkov:skip=CKV2_AWS_62:event notifications innecesarias, no hay consumidor de eventos de este bucket (CloudFront es el unico reader).
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 server access logs del bucket frontend hacia el bucket access-logs compartido.
# Habilita visibilidad de accesos directos (no via CloudFront) por si el OAC se rompe.
resource "aws_s3_bucket_logging" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "frontend-s3-access-logs/"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    # checkov:skip=CKV_AWS_300:abort_incomplete_multipart_upload no implementado. Los assets de build son pequenos (<10MB) y el costo de uploads incompletos es despreciable. Se puede agregar via bloque `abort_incomplete_multipart_upload { days_after_initiation = 7 }` en una sesion futura (mismo FU-1 que modules/storage-sam-artifacts).
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    filter {}
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.bucket_name_prefix}-${var.environment}-oac"
  description                       = "OAC para ${local.bucket_name} (Spark Match 04-frontend deploy role)."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  # checkov:skip=CKV_AWS_310:origin failover requiere 2 origins (activo + pasivo). El frontend Spark Match tiene un unico origin S3 -- failover cross-region esta fuera de scope.
  # checkov:skip=CKV_AWS_374:geo restriction deshabilitada por default (decision de producto: publico global). Se puede activar via restrictions.geo_restriction.locations cuando se defina el alcance geografico.
  # checkov:skip=CKV_AWS_68:WAF no esta en el scope actual. Plan: AWS WAF WebACL compartido por todas las distribuciones del proyecto en una sesion dedicada (costo ~$5/mes + $1/mes por regla).
  # checkov:skip=CKV2_AWS_32:response headers policy no configurada en esta fase (defer). El comportamiento por default de CloudFront ya sirve HTML estatico de forma segura.
  # checkov:skip=CKV2_AWS_42:custom SSL certificate requiere dominio custom (sin aliases en esta fase, defer). Se usa cloudfront_default_certificate=true (*.cloudfront.net) hasta que se asigne un dominio custom.
  # checkov:skip=CKV2_AWS_47:WAFv2 con regla AMR para Log4j -- depende de WAF (mismo defer que CKV_AWS_68).
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Spark Match frontend (${var.environment})"
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.access_logs.bucket_domain_name
    prefix          = local.log_prefix
  }

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-${local.bucket_name}"

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.min_protocol_version
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = local.common_tags

  # aws_s3_bucket_acl.access_logs es obligatorio aca aunque parezca redundante.
  # `logging_config` solo referencia aws_s3_bucket.access_logs.bucket_domain_name,
  # asi que la unica arista implicita que Terraform deduce es contra el BUCKET,
  # no contra su ACL. Pero CloudFront standard logging exige que el bucket
  # destino tenga ACLs habilitadas para poder escribir el grant FULL_CONTROL de
  # awslogsdelivery, y desde abril 2023 todo bucket S3 nace con
  # BucketOwnerEnforced (ACLs deshabilitadas). Sin esta arista, Terraform puede
  # emitir CreateDistribution antes del ownership_controls + acl del bucket de
  # logs y AWS responde InvalidArgument. En dev no exploto por suerte en el
  # orden, no por garantia.
  #
  # Con una sola entrada basta: aws_s3_bucket_acl.access_logs ya declara
  # depends_on sobre aws_s3_bucket_ownership_controls.access_logs, asi que el
  # ownership entra en el grafo por transitividad.
  depends_on = [
    aws_s3_bucket_ownership_controls.frontend,
    aws_s3_bucket_acl.access_logs,
  ]
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "FrontendHttpsOnlyAndCloudFrontOAC"
    Statement = [
      {
        Sid       = "HTTPSOnly"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "CloudFrontOAReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      },
    ]
  })

  depends_on = [aws_cloudfront_distribution.frontend]
}

resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_144:log bucket, replication innecesaria.
  # checkov:skip=CKV_AWS_145:log bucket cifrado con SSE-S3 (AES256). SSE-KMS requiere permisos adicionales sobre la CMK para el servicio de log delivery (logging.s3.amazonaws.com); no aplica a un log bucket.
  # checkov:skip=CKV_AWS_18:este ES el bucket de logs; logging sobre si mismo es circular y no aporta valor (excepcion estandar de la industria para buckets destino de access logs).
  # checkov:skip=CKV_AWS_21:versioning no habilitado en log bucket (costo extra de storage por cada version de log entry; los logs son regenerables).
  # checkov:skip=CKV2_AWS_62:log bucket, event notifications innecesarias.
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

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# CloudFront log delivery (delivery.logs.amazonaws.com) requires ACL log-delivery-write
# on the destination bucket. With BucketOwnerEnforced this is rejected; BucketOwnerPreferred
# allows the ACL while keeping ObjectOwnership enforced for all new objects.
resource "aws_s3_bucket_acl" "access_logs" {
  depends_on = [aws_s3_bucket_ownership_controls.access_logs]

  bucket = aws_s3_bucket.access_logs.id
  acl    = "log-delivery-write"
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
  bucket = aws_s3_bucket.access_logs.id

  rule {
    # checkov:skip=CKV_AWS_300:abort_incomplete_multipart_upload no implementado en log bucket (casi nunca hay uploads multipart al log bucket; logs son append-only).
    id     = "expire-old-access-logs"
    status = "Enabled"

    expiration {
      days = var.access_logs_retention_days
    }

    filter {}
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
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
            "aws:SourceArn" = aws_s3_bucket.frontend.arn
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
