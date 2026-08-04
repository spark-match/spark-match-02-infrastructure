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
  description = "Nombre del entorno. Determina el nombre del bucket."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados al bucket."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "ARN de la CMK de KMS para cifrar el bucket con SSE-KMS. Si null, usa SSE-S3 (AES256)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Dias antes de expirar versiones no-actuales de objetos (housekeeping de artefactos de build viejos)."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days debe ser >= 1."
  }
}

variable "force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket aunque tenga objetos. true en dev para facilitar cleanup; false en prod (evita borrado accidental de artefactos de deploy vigentes)."
  type        = bool
  default     = false
}

variable "access_logs_retention_days" {
  description = "Dias antes de expirar los server access logs del bucket de artefactos."
  type        = number
  default     = 90

  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "access_logs_retention_days debe ser >= 1."
  }
}
