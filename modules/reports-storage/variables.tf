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
  description = "Tags adicionales aplicados a los buckets."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "ARN de la CMK para cifrar los informes con SSE-KMS. Si null cae a SSE-S3 (AES256), que para datos psicometricos de menores NO es lo deseable: sin CMK, el acceso al texto plano depende solo del permiso de S3 y no de un permiso de KMS auditable y revocable. Dejarlo en null solo tiene sentido en un entorno de pruebas sin datos reales."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Dias antes de expirar versiones NO ACTUALES de un objeto. No afecta a ningun informe vigente: cada informe nuevo va a una key nueva, asi que solo aparecen versiones no-actuales si se re-renderiza el PDF sobre la misma key. El periodo de retencion de los informes en si esta sin decidir a proposito -- ver el comentario del lifecycle en main.tf."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days debe ser >= 1."
  }
}

variable "force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket aunque tenga objetos. Mantener en false salvo en un entorno de pruebas: aqui los objetos son informes de estudiantes, no artefactos regenerables de build."
  type        = bool
  default     = false
}

variable "access_logs_retention_days" {
  description = "Dias antes de expirar los server access logs del bucket de informes. Sobre datos personales, estos logs son el registro de quien leyo que y cuando, asi que conviene no bajarlo sin pensarlo."
  type        = number
  default     = 365

  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "access_logs_retention_days debe ser >= 1."
  }
}
