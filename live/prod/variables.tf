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
  description = "Si crear todos los interface endpoints (SSM, ECR, Logs, Secrets, Bedrock, KMS, STS, events, etc.). false en prod (checkpoint de costos 2026-08-04): con NAT presente, solo los servicios realmente usados necesitan endpoint dedicado -- el resto sale por NAT. Los 11 endpoints x 2 AZ costaban ~$160.60/mes (22 ENI); con enabled_endpoints explicito + 1 sola AZ el costo baja a ~$29.20/mes."
  type        = bool
  default     = false
}

variable "enabled_endpoints" {
  description = "Lista explicita de interface endpoints a crear (con enable_all_endpoints_by_default=false). Prod necesita secretsmanager (credenciales RDS), events (PutEvents a EventBridge), ssm (config ADR-0002 para Lambdas en VPC) y bedrock-runtime (el deep-agent invoca Bedrock desde subnets privadas)."
  type        = list(string)
  default     = ["secretsmanager", "events", "ssm", "bedrock-runtime"]
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
# Nota: interface_endpoint_subnet_ids no se declara como variable aca -- se
# calcula inline en main.tf con slice(module.networking.private_subnet_ids,
# 0, 1) (1 sola AZ, mismo patron que live/dev/main.tf) para el recorte de
# costos del checkpoint 2026-08-04.

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

# cors_allowed_origins no se declara en prod. A diferencia de dev, donde el
# valor es la constante "*", en prod el origen permitido es el dominio de la
# distribucion CloudFront, que no existe hasta que se aplique este mismo
# directorio. Ninguna constante podia ser correcta, y el placeholder que habia
# aqui arrastraba un TODO imposible de cumplir. Se deriva del output del
# modulo en main.tf; ver la nota junto a module "ssm_bootstrap".

variable "rds_backup_retention_period_days" {
  description = "Dias de retencion de backups automaticos de RDS. Se queda en 0 en prod, igual que dev: la cuenta AWS 681526276858 tiene guardrails de 'Free Tier account' que rechazan CreateDBInstance con FreeTierRestrictionError si este valor es > 0, y prod usa LA MISMA cuenta que dev (ver AGENTS.md tabla Multi-env). DECISION TOMADA el 2026-08-07, no pendiente: spark-match es un proyecto de curso y el objetivo es ejercitar las tecnologias, no sostener un servicio con compromiso de recuperacion. Se descartaron sacar la cuenta del plan Free Tier y montar snapshots manuales. Consecuencia: prod no tiene backups de base de datos; si se pierde la instancia, se pierden los datos. Cambiar esta linea exige antes sacar la cuenta del Free Tier o mover prod a una cuenta propia."
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

###############################################################################
# Variables para modules/ecr + modules/agent-service (spark-match-08-deep-agent)
###############################################################################

variable "enable_agent_service" {
  description = "Si crear el repositorio ECR y el servicio ECS del deep-agent. Interruptor de costo: apagarlo destruye el ALB (~$17.50/mes) y las tasks Fargate (~$18/mes). true en prod: el agente es parte del producto."
  type        = bool
  default     = true
}

variable "agent_ecr_force_delete" {
  description = "Si permitir que `terraform destroy` borre el repositorio ECR aunque tenga imagenes. false en prod: protege la imagen que esta corriendo en el servicio."
  type        = bool
  default     = false
}

variable "agent_task_cpu" {
  description = "CPU units de la task Fargate del agente (512 = 0.5 vCPU). Punto de partida conservador; ajustar segun metricas reales de latencia de Bedrock."
  type        = number
  default     = 512
}

variable "agent_task_memory" {
  description = "Memoria en MiB de la task Fargate del agente."
  type        = number
  default     = 1024
}

variable "agent_desired_count" {
  description = "Cuantas tasks del agente correr. 1 en el arranque de prod: el estado de conversacion vive en Postgres (schema `agent`), no en memoria, asi que escalar es solo subir este numero cuando el trafico lo justifique."
  type        = number
  default     = 1
}

variable "agent_log_retention_days" {
  description = "Retencion del log group del servicio del agente. 365 en prod: mismo minimo de 1 anio que exige CKV_AWS_338 para el resto de los log groups productivos."
  type        = number
  default     = 365
}

variable "agent_enable_deletion_protection" {
  description = "Si proteger el ALB del agente contra borrado. true en prod: el DNS del ALB queda publicado en SSM y consumido por el frontend, un destroy accidental cortaria el chat."
  type        = bool
  default     = true
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "spark-match/spark-match-02-infrastructure"
  }
}
