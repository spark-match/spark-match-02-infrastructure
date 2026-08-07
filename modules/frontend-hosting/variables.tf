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

variable "min_protocol_version" {
  description = "Minimum TLS protocol version para viewers de CloudFront."
  type        = string
  default     = "TLSv1.2_2021"

  validation {
    condition     = contains(["TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021", "TLSv1.3_2025"], var.min_protocol_version)
    error_message = "min_protocol_version invalido. Valores permitidos: TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021, TLSv1.3_2025."
  }
}

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
