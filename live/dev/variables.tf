variable "aws_region" {
  description = "Region AWS donde desplegar la infraestructura."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string
  default     = "spark-match"
}

variable "environment" {
  description = "Nombre del entorno (dev, staging, prod). Determina nombres de recursos, OIDC trust policies y tagging."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

###############################################################################
# Variables para module "networking" (Fase 1.5)
###############################################################################

variable "vpc_cidr" {
  description = "CIDR principal de la VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "azs" {
  description = "Lista de AZs donde crear subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subnets publicas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subnets privadas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Si crear NAT Gateway(s) para que las subnets privadas tengan salida a internet. False util para dev offline."
  type        = bool
  default     = false
}

variable "enable_nat_ha" {
  description = "Si crear un NAT por AZ (HA). Si false, 1 NAT compartido en la primera subnet publica. Costo extra ~$64/mes si true."
  type        = bool
  default     = false
}

###############################################################################
# Variables para module "endpoints" (Fase 1.5)
###############################################################################

variable "enable_all_endpoints_by_default" {
  description = "Si crear todos los interface endpoints (SSM, ECR, Logs, Secrets, Bedrock, KMS, STS, etc.). Costo ~$72/mes en prod."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Si crear VPC Flow Logs hacia CloudWatch Logs. Costo bajo pero no nulo. Default false en dev, true en prod."
  type        = bool
  default     = false
}

variable "flow_log_traffic_type" {
  description = "Tipo de trafico a loguear en VPC Flow Logs: ACCEPT, REJECT, o ALL. Default REJECT."
  type        = string
  default     = "REJECT"
}

variable "flow_log_retention_days" {
  description = "Retention en dias del log group de flow logs."
  type        = number
  default     = 30
}

variable "enable_s3_gateway_endpoint" {
  description = "Si crear el S3 gateway endpoint (gratis). Recomendado true siempre."
  type        = bool
  default     = true
}

###############################################################################
# Variables para module "security" (Fase 1.5)
###############################################################################

variable "kms_deletion_window_in_days" {
  description = "Periodo de espera para borrar el CMK de KMS. 7 dias en dev, 30 en prod."
  type        = number
  default     = 7
}

variable "sam_deploy_github_repos" {
  description = "Repos de GitHub permitidos a asumir spark-match-sam-deploy-{env}."
  type        = list(string)
  default     = ["spark-match/spark-match-03-backend"]
}

variable "bedrock_deploy_github_repos" {
  description = "Repos de GitHub permitidos a asumir spark-match-bedrock-agentcore-deploy-{env}."
  type        = list(string)
  default     = ["spark-match/spark-match-08-deep-agent"]
}

###############################################################################
# Variables para module "endpoints" (Fase 2 — Lambda dentro de VPC, ADR 0002 §4)
###############################################################################

variable "enabled_endpoints" {
  description = "Lista explicita de interface endpoints a crear (con enable_all_endpoints_by_default=false). Dev necesita solo secretsmanager (leer credenciales frescas de RDS) y events (PutEvents a EventBridge); ver ADR 0002."
  type        = list(string)
  default     = ["secretsmanager", "events"]
}

###############################################################################
# Variables para modules de Fase 2 (storage, secrets, events, dynamodb, rds, ssm)
###############################################################################

variable "sam_artifacts_force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket de artefactos SAM aunque tenga objetos. true en dev para facilitar cleanup e iteracion."
  type        = bool
  default     = true
}

variable "secrets_recovery_window_in_days" {
  description = "Dias de gracia antes de borrar definitivamente un secret de Secrets Manager (JWT y credenciales de RDS) tras un delete. 0 = borrado inmediato, recomendado en dev para poder recrear el mismo secret sin esperar el recovery window."
  type        = number
  default     = 0

  validation {
    condition     = var.secrets_recovery_window_in_days == 0 || (var.secrets_recovery_window_in_days >= 7 && var.secrets_recovery_window_in_days <= 30)
    error_message = "secrets_recovery_window_in_days debe ser 0 o estar entre 7 y 30."
  }
}

variable "cors_allowed_origins" {
  description = "Origenes CORS permitidos por el backend, comma-separated. '*' en dev; lista explicita de dominios en prod."
  type        = string
  default     = "*"
}

variable "rds_backup_retention_period_days" {
  description = "Dias de retencion de backups automaticos de RDS. 0 en dev: la cuenta AWS 681526276858 tiene guardrails de 'Free Tier account' que rechazan CreateDBInstance (FreeTierRestrictionError) si este valor es > 0. Prod debe usar >= 7."
  type        = number
  default     = 0

  validation {
    condition     = var.rds_backup_retention_period_days >= 0 && var.rds_backup_retention_period_days <= 35
    error_message = "rds_backup_retention_period_days debe estar entre 0 y 35."
  }
}

###############################################################################
# Variables para modules/frontend-hosting + modules/oidc-frontend
###############################################################################

variable "frontend_force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket frontend aunque tenga objetos. true en dev para iterar rapido; false en prod (proteger deploys vigentes)."
  type        = bool
  default     = true
}

variable "frontend_access_logs_retention_days" {
  description = "Dias antes de expirar los CloudFront access logs en el bucket access-logs del frontend. 30 en dev, 90 en prod."
  type        = number
  default     = 30

  validation {
    condition     = var.frontend_access_logs_retention_days >= 1
    error_message = "frontend_access_logs_retention_days debe ser >= 1."
  }
}

variable "frontend_noncurrent_version_expiration_days" {
  description = "Dias antes de expirar versiones no-actuales del bucket frontend. 30 en dev, 90 en prod."
  type        = number
  default     = 30

  validation {
    condition     = var.frontend_noncurrent_version_expiration_days >= 1
    error_message = "frontend_noncurrent_version_expiration_days debe ser >= 1."
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "spark-match/spark-match-02-infrastructure"
  }
}
