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

# Nota (2026-08-01): las variables placeholder para module "networking",
# module "endpoints" y module "security" (vpc_cidr, azs, public_subnet_cidrs,
# private_subnet_cidrs, enable_nat_gateway, enable_nat_ha,
# enable_all_endpoints_by_default, enable_flow_logs, flow_log_traffic_type,
# flow_log_retention_days, enable_s3_gateway_endpoint, kms_deletion_window_in_days,
# sam_deploy_github_repos, bedrock_deploy_github_repos) fueron removidas de
# live/prod/variables.tf porque live/prod/main.tf no las consume todavia.
# Sprint 4 / 03 wire-all-modules reintroducira las variables cuando se wireen
# los modules a prod. Mientras tanto, el rule tflint terraform_unused_declarations
# reportaba 15 warnings y bloqueaba CI bajo el ruleset strict (PR #200 devops).
# Tracking: sprint-2/01b-tflint-fix-unused-decls.

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "spark-match/spark-match-02-infrastructure"
  }
}
