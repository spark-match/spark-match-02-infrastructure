variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en el nombre del role."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno. Determina la branch permitida (dev -> refs/heads/dev, prod -> refs/heads/main) y el environment de GitHub."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados al role."
  type        = map(string)
  default     = {}
}

variable "repo" {
  description = "Repo de GitHub permitido a asumir el role (formato OWNER/REPO)."
  type        = string
  default     = "spark-match/spark-match-04-frontend"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.repo))
    error_message = "repo debe tener formato OWNER/REPO (ej: spark-match/spark-match-04-frontend)."
  }
}

variable "bucket_arn" {
  description = "ARN del bucket S3 del frontend (output frontend_bucket_arn de modules/frontend-hosting)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:s3:::", var.bucket_arn))
    error_message = "bucket_arn debe ser un ARN valido de S3."
  }
}

variable "access_logs_bucket_arn" {
  description = "ARN del bucket access-logs del frontend (output access_logs_bucket_arn de modules/frontend-hosting)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:s3:::", var.access_logs_bucket_arn))
    error_message = "access_logs_bucket_arn debe ser un ARN valido de S3."
  }
}

variable "distribution_arn" {
  description = "ARN de la distribucion CloudFront (output frontend_distribution_arn de modules/frontend-hosting)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:cloudfront::", var.distribution_arn))
    error_message = "distribution_arn debe ser un ARN valido de CloudFront."
  }
}

variable "iam_role_max_session_duration" {
  description = "Maxima duracion de la sesion del role (segundos). 3600 = 1h (default). 43200 = 12h (max AWS)."
  type        = number
  default     = 3600

  validation {
    condition     = var.iam_role_max_session_duration >= 3600 && var.iam_role_max_session_duration <= 43200
    error_message = "iam_role_max_session_duration debe estar entre 3600 (1h) y 43200 (12h)."
  }
}
