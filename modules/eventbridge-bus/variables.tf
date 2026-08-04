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
  description = "Nombre del entorno. Determina el nombre del bus (spark-match-events-{env})."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "archive_retention_days" {
  description = "Dias de retencion del archive de EventBridge. 0 = para siempre."
  type        = number
  default     = 30

  validation {
    condition     = var.archive_retention_days >= 0
    error_message = "archive_retention_days debe ser >= 0."
  }
}

variable "dlq_message_retention_seconds" {
  description = "Segundos de retencion de mensajes en la DLQ. Default 14 dias (el maximo soportado por SQS)."
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds debe estar entre 60 y 1209600 (14 dias, maximo de SQS)."
  }
}

variable "kms_key_arn" {
  description = "ARN de la CMK de KMS para cifrar la DLQ. Si null, usa SSE-SQS (cifrado administrado por AWS, gratis)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}
