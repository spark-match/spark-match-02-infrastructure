variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno. Determina el nombre del bucket y los tags."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a los recursos."
  type        = map(string)
  default     = {}
}

variable "bucket_name_prefix" {
  description = "Prefijo del nombre del bucket S3. El nombre final es {prefix}-{env}."
  type        = string
  default     = "spark-match-frontend"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.bucket_name_prefix))
    error_message = "bucket_name_prefix debe ser kebab-case lowercase (3-40 chars, solo [a-z0-9-])."
  }
}

variable "force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket aunque tenga objetos. true en dev para iterar rapido, false en prod (proteger deploys vigentes)."
  type        = bool
  default     = false
}

variable "access_logs_retention_days" {
  description = "Dias antes de expirar los logs de acceso de CloudFront en el bucket access-logs."
  type        = number
  default     = 90

  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "access_logs_retention_days debe ser >= 1."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Dias antes de expirar versiones no-actuales del bucket frontend (housekeeping de builds viejos)."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days debe ser >= 1."
  }
}

variable "price_class" {
  description = "Price class de CloudFront. PriceClass_100 = Norteamerica+Europa (costo minimo). PriceClass_All = global."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class debe ser PriceClass_100, PriceClass_200, o PriceClass_All."
  }
}

# Aqui habia `min_protocol_version`. Se elimina porque su unico consumidor,
# el bloque `viewer_certificate` de aws_cloudfront_distribution.frontend, ya
# no la usa: con el certificado por defecto de CloudFront el valor es inerte
# y solo producia deriva permanente. La nota completa esta junto a ese bloque
# en main.tf. Se quita en vez de dejarla huerfana porque .tflint.hcl tiene
# activo `terraform_unused_declarations`.
#
# Cuando llegue el dominio custom, esta variable vuelve junto con
# `acm_certificate_arn` y `ssl_support_method`, que es cuando el valor pasa a
# significar algo.

variable "enable_kms_encryption" {
  description = "Si cifrar el bucket frontend con SSE-KMS usando la CMK del proyecto (module.kms). false por default (AES256)."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN de la CMK de KMS. Requerido solo si enable_kms_encryption=true."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}
