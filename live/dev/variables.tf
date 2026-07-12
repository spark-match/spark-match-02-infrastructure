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

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "spark-match/spark-match-02-infrastructure"
  }
}
