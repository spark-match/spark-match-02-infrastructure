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
  description = "Nombre del entorno. Determina el nombre de la tabla (spark-match-{env}-idempotency)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a la tabla."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "ARN de la CMK de KMS para cifrar la tabla. Si null, usa la key administrada por AWS (alias/aws/dynamodb)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Si habilitar point-in-time recovery (PITR). Costo bajo con PAY_PER_REQUEST y tabla pequena; default true."
  type        = bool
  default     = true
}
