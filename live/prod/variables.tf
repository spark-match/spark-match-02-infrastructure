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
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

###############################################################################
# Variables para module "networking"
###############################################################################

variable "vpc_cidr" {
  description = "CIDR principal de la VPC. Separado de dev (10.10.0.0/16) para evitar colisiones si en algun momento se hace VPC peering o Transit Gateway entre envs."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Lista de AZs donde crear subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subnets publicas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subnets privadas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Si crear NAT Gateway(s) para que las subnets privadas tengan salida a internet. true en prod (a diferencia de dev): las Lambdas de prod pueden necesitar salida a internet generica (ej. APIs externas) ademas de los VPC endpoints."
  type        = bool
  default     = true
}

variable "enable_nat_ha" {
  description = "Si crear un NAT por AZ (HA). true en prod: la caida de una AZ no deja a las Lambdas sin salida a internet. Costo extra ~$64/mes (2 NAT Gateway + 2 EIP)."
  type        = bool
  default     = true
}

###############################################################################
# Variables para module "endpoints"
###############################################################################

variable "enable_all_endpoints_by_default" {
  description = "Si crear todos los interface endpoints (SSM, ECR, Logs, Secrets, Bedrock, KMS, STS, events, etc.). true en prod para mantener trafico AWS privado (sin atravesar NAT ni internet). Costo ~$72/mes (10-11 interface endpoints x $0.01/h)."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Si crear VPC Flow Logs hacia CloudWatch Logs. true en prod para auditoria y debugging de trafico rechazado."
  type        = bool
  default     = true
}

variable "flow_log_traffic_type" {
  description = "Tipo de trafico a loguear en VPC Flow Logs: ACCEPT, REJECT, o ALL. REJECT en prod (trafico denegado, util para detectar intentos de acceso no autorizado sin el volumen/costo de loguear todo)."
  type        = string
  default     = "REJECT"
}

variable "flow_log_retention_days" {
  description = "Retention en dias del log group de flow logs. 365 dias en prod (vs 30 en dev) -- cumple CKV_AWS_338 (minimo 1 anio) ademas de dar ventana de auditoria mas larga."
  type        = number
  default     = 365
}

variable "enable_s3_gateway_endpoint" {
  description = "Si crear el S3 gateway endpoint (gratis). Recomendado true siempre."
  type        = bool
  default     = true
}

###############################################################################
# Variables para module "security" (kms, oidc-github)
###############################################################################

variable "kms_deletion_window_in_days" {
  description = "Periodo de espera para borrar el CMK de KMS. 30 dias en prod (maximo AWS, estandar para CMK productiva -- da tiempo de rollback ante un destroy accidental)."
  type        = number
  default     = 30
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
# Variables para modules de Fase 2 (storage, secrets, events, dynamodb, rds, ssm)
###############################################################################
# Nota: enabled_endpoints e interface_endpoint_subnet_ids (usadas en dev) NO
# se declaran aca a proposito: con enable_all_endpoints_by_default=true el
# modulo endpoints ignora enabled_endpoints, y con
# interface_endpoint_subnet_ids sin pasar (default []) usa automaticamente
# TODAS las private_subnet_ids (ambas AZs) -- exactamente lo que prod quiere
# para alta disponibilidad. Ver modules/endpoints/main.tf locals.

variable "sam_artifacts_force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket de artefactos SAM aunque tenga objetos. false en prod (evita borrado accidental de artefactos de deploy vigentes; a diferencia de dev que usa true para iterar rapido)."
  type        = bool
  default     = false
}

variable "secrets_recovery_window_in_days" {
  description = "Dias de gracia antes de borrar definitivamente un secret de Secrets Manager (JWT y credenciales de RDS) tras un delete. 30 en prod (maximo, protege contra borrado accidental); 0 en dev para poder recrear el mismo secret sin esperar."
  type        = number
  default     = 30

  validation {
    condition     = var.secrets_recovery_window_in_days == 0 || (var.secrets_recovery_window_in_days >= 7 && var.secrets_recovery_window_in_days <= 30)
    error_message = "secrets_recovery_window_in_days debe ser 0 o estar entre 7 y 30."
  }
}

variable "cors_allowed_origins" {
  description = "Origenes CORS permitidos por el backend, comma-separated. TODO: reemplazar el placeholder por el dominio real de spark-match-04-frontend antes del primer apply real a prod (el frontend aun no existe/despliega)."
  type        = string
  default     = "https://TODO-set-real-frontend-domain.spark-match.example"
}

variable "rds_backup_retention_period_days" {
  description = "Dias de retencion de backups automaticos de RDS. 0 en prod (igual que dev): la cuenta AWS 681526276858 tiene guardrails de 'Free Tier account' que rechazan CreateDBInstance (FreeTierRestrictionError) si este valor es > 0, y prod usa LA MISMA cuenta que dev (ver AGENTS.md tabla Multi-env). Esto es un riesgo operacional conocido y aceptado por ahora -- sin backups automaticos de RDS en prod. Revisar antes del primer apply real: upgrade del tipo de cuenta AWS, o cuenta separada para prod, para poder usar >= 7 dias."
  type        = number
  default     = 0

  validation {
    condition     = var.rds_backup_retention_period_days >= 0 && var.rds_backup_retention_period_days <= 35
    error_message = "rds_backup_retention_period_days debe estar entre 0 y 35."
  }
}

variable "db_instance_class" {
  description = "Clase de instancia RDS para prod. db.t4g.small (2GiB RAM) como punto de partida conservador -- mas grande que dev (db.t4g.micro, 1GiB) pero sin sobre-aprovisionar antes de tener datos reales de carga. Ajustar segun metricas post-launch."
  type        = string
  default     = "db.t4g.small"
}

###############################################################################
# Variables para modules/frontend-hosting + modules/oidc-frontend
###############################################################################

variable "frontend_force_destroy" {
  description = "Si permitir que terraform destroy borre el bucket frontend aunque tenga objetos. false en prod (proteger deploys vigentes); true en dev para iterar rapido."
  type        = bool
  default     = false
}

variable "frontend_access_logs_retention_days" {
  description = "Dias antes de expirar los CloudFront access logs en el bucket access-logs del frontend. 90 en prod (auditoria)."
  type        = number
  default     = 90

  validation {
    condition     = var.frontend_access_logs_retention_days >= 1
    error_message = "frontend_access_logs_retention_days debe ser >= 1."
  }
}

variable "frontend_noncurrent_version_expiration_days" {
  description = "Dias antes de expirar versiones no-actuales del bucket frontend. 90 en prod (auditoria)."
  type        = number
  default     = 90

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
