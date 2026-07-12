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
  description = "Nombre del entorno. Determina nombres de recursos, trust policies OIDC y tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "ID de la VPC donde se crean los security groups (output de modules/networking)."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id debe tener formato vpc-<hex> (8-17 chars)."
  }
}

variable "vpc_cidr" {
  description = "CIDR principal de la VPC. Usado para el egress rule del SG de Lambdas."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR valido (ej. 10.0.0.0/16)."
  }
}

variable "create_lambda_sg_rules" {
  description = "Si crear las rules por defecto del SG de Lambdas (egress VPC + egress HTTPS internet). Poner a false durante bootstrap si el SG ya existe con otras rules."
  type        = bool
  default     = true
}

variable "create_rds_sg_rules" {
  description = "Si crear la rule de ingress del SG de RDS (5432 desde sg-lambda)."
  type        = bool
  default     = true
}

variable "create_endpoints_sg_rules" {
  description = "Si crear la rule de ingress del SG de endpoints (443 desde sg-lambda)."
  type        = bool
  default     = true
}

variable "kms_deletion_window_in_days" {
  description = "Periodo de gracia para borrar la CMK. 30 dias es el minimo razonable. 7 es estricto para dev/staging."
  type        = number
  default     = 30

  validation {
    condition     = contains([7, 14, 30, 60, 90, 120, 180, 365], var.kms_deletion_window_in_days)
    error_message = "Deletion window debe estar en [7, 14, 30, 60, 90, 120, 180, 365]."
  }
}

variable "sam_deploy_github_repos" {
  description = "Repos GitHub permitidos en el trust policy de spark-match-sam-deploy. Sub claim patterns se derivan automaticamente."
  type        = list(string)
  default     = ["spark-match/spark-match-03-backend"]

  validation {
    condition     = length(var.sam_deploy_github_repos) > 0
    error_message = "sam_deploy_github_repos no puede estar vacio."
  }
}

variable "bedrock_deploy_github_repos" {
  description = "Repos GitHub permitidos en el trust policy de spark-match-bedrock-agentcore-deploy."
  type        = list(string)
  default     = ["spark-match/spark-match-08-deep-agent"]

  validation {
    condition     = length(var.bedrock_deploy_github_repos) > 0
    error_message = "bedrock_deploy_github_repos no puede estar vacio."
  }
}

variable "iam_role_max_session_duration" {
  description = "Duracion maxima de la sesion (en segundos) para los 4 roles IAM creados por este modulo. Rango AWS: 3600-43200. Default 3600 (1h)."
  type        = number
  default     = 3600

  validation {
    condition     = var.iam_role_max_session_duration >= 3600 && var.iam_role_max_session_duration <= 43200
    error_message = "iam_role_max_session_duration debe estar entre 3600 (1h) y 43200 (12h)."
  }
}
