variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string
  default     = "spark-match"
}

variable "environment" {
  description = "Nombre del entorno (dev, staging, prod)."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "ID de la VPC donde se crean los security groups (output de modules/networking)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR principal de la VPC. Usado para el egress rule del SG de Lambdas."
  type        = string
  default     = "10.0.0.0/16"
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
}

variable "bedrock_deploy_github_repos" {
  description = "Repos GitHub permitidos en el trust policy de spark-match-bedrock-agentcore-deploy."
  type        = list(string)
  default     = ["spark-match/spark-match-08-deep-agent"]
}
