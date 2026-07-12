variable "project_name" {
  description = "Nombre del proyecto."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars)."
  }
}

variable "environment" {
  description = "Entorno (dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales."
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "Region AWS. Necesaria para componer los service_name de los VPC endpoints."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID de la VPC (output de modules/networking)."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id debe tener formato vpc-<hex>."
  }
}

variable "private_subnet_ids" {
  description = "IDs de las subnets privadas (output de modules/networking) donde se crean los interface endpoints."
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "IDs de las route tables privadas (output de modules/networking) para asociar el gateway endpoint de S3."
  type        = list(string)
}

variable "endpoints_security_group_id" {
  description = "ID del SG para VPC endpoints (output de modules/security). Este SG debe permitir ingress 443 desde sg-lambda."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.endpoints_security_group_id))
    error_message = "endpoints_security_group_id debe tener formato sg-<hex>."
  }
}

variable "enable_all_endpoints_by_default" {
  description = "Si crear todos los interface endpoints posibles. Setear false en dev/staging si se quiere reducir costo (cada endpoint cobra $0.01/h = ~$7.20/mes)."
  type        = bool
  default     = true
}

variable "enabled_endpoints" {
  description = "Lista explicita de interface endpoints a crear (cuando enable_all_endpoints_by_default=false). Valores validos: ssm, ssmmessages, ec2messages, secretsmanager, kms, logs, ecr.api, ecr.dkr, bedrock-runtime, sts."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ep in var.enabled_endpoints : contains([
        "ssm", "ssmmessages", "ec2messages", "secretsmanager",
        "kms", "logs", "ecr.api", "ecr.dkr", "bedrock-runtime", "sts",
      ], ep)
    ])
    error_message = "Cada valor de enabled_endpoints debe estar en [ssm, ssmmessages, ec2messages, secretsmanager, kms, logs, ecr.api, ecr.dkr, bedrock-runtime, sts]."
  }
}

variable "enable_s3_gateway_endpoint" {
  description = "Si crear el VPC endpoint gateway para S3 (gratis). Recomendado true siempre para que las descargas de ECR/Lambda no salgan por NAT."
  type        = bool
  default     = true
}
