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
  description = "Nombre del entorno. Determina el alias de la CMK."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a la CMK."
  type        = map(string)
  default     = {}
}

variable "deletion_window_in_days" {
  description = "Periodo de gracia para borrar la CMK. 30 dias es el minimo razonable. 7 es estricto para dev/staging."
  type        = number
  default     = 30

  validation {
    condition     = contains([7, 14, 30, 60, 90, 120, 180, 365], var.deletion_window_in_days)
    error_message = "Deletion window debe estar en [7, 14, 30, 60, 90, 120, 180, 365]."
  }
}

variable "user_role_arns" {
  description = "ARNs de los IAM roles que pueden usar (kms:Encrypt/Decrypt/etc) la CMK. Por defecto son los 4 roles extraidos a modules/oidc-github (sam_deploy, bedrock_deploy, lambda_runtime, agentcore_runtime). El caller (live/*/main.tf) pasa los ARNs cross-module desde `module.oidc_github.*_role_arn`."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.user_role_arns) >= 0
    error_message = "user_role_arns debe ser una lista (puede estar vacia si no hay roles)."
  }
}

variable "aws_service_principals" {
  description = "AWS service principals que pueden usar la CMK (logs, ssm, secretsmanager, s3, bedrock, rds, dynamodb, sqs). Default: 8 servicios comunes en spark-match."
  type        = list(string)
  default = [
    "logs",
    "ssm",
    "secretsmanager",
    "s3",
    "bedrock",
    "rds",
    "dynamodb",
    "sqs",
  ]
}
