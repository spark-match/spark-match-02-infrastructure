###############################################################################
# Spark Match - Infraestructura dev
###############################################################################
#
# Fase 0 (completada):
#   - Sin recursos aplicados (cuenta AWS 681526276858 limpia salvo tfstate backend).
#   - State bucket: spark-match-tfstate-dev con versioning + native lockfile.
#
# Fase 1 (activa):
#   - module "networking" -> VPC 10.10.0.0/16, NAT OFF, 1 subnet publica + 1 privada por AZ
#   - module "security"   -> IAM roles *-dev, KMS CMK dev, SGs (Fase 1.5)
#   - module "endpoints"  -> Solo S3 gateway (no interface endpoints en dev por costo)
#
# Fases futuras:
#   - module "database"     -> RDS Aurora PostgreSQL Serverless v2 (sin pgvector; vector store en otro proveedor)
#   - module "storage"      -> S3 buckets definitivos
#   - module "events"       -> EventBridge bus custom + archive + DLQ
#   - module "secrets"      -> Secrets Manager (JWT, DB credentials)
#   - module "monitoring"   -> CloudWatch + SNS
#   - module "bedrock"      -> IAM para Bedrock + ECR repo del agente
#
# Politica de cambios:
#   - Cualquier cambio aca requiere PR aprobado por @spark-match/devops.
#   - Apply va por push a rama `dev` o workflow_dispatch con environment=dev.
#   - GH Environment "dev" (sin required reviewers) aprueba automaticamente.
###############################################################################

###############################################################################
# Module: networking
###############################################################################
# VPC principal + 2 subnets publicas + 2 subnets privadas (1 por AZ en us-east-1a/b).
# NAT gateway desactivado en dev (las Lambdas corren fuera de VPC por decision
# arquitectonica Opcion A, IMPROVEMENTS.md A4/NET-01).
# Flow logs desactivados en dev para minimizar costo (default false).
#
# Outputs consumidos por modules/security y modules/endpoints (Fase 1.5):
#   - vpc_id, public_subnet_ids, private_subnet_ids, private_route_table_ids
###############################################################################

module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # NAT desactivado en dev: sin salida a internet para subnets privadas.
  # Las Lambdas de 03-backend y 08-deep-agent corren fuera de VPC.
  enable_nat_gateway = var.enable_nat_gateway
  enable_nat_ha      = var.enable_nat_ha

  # Flow logs desactivados en dev (default false).
  # Se puede activar via -var si se necesita debuggear trafico de red.
  enable_flow_logs        = var.enable_flow_logs
  flow_log_traffic_type   = var.flow_log_traffic_type
  flow_log_retention_days = var.flow_log_retention_days

  # KMS key se seteara en Fase 1.5 cuando module.security cree el CMK.
  # Por ahora null: AWS usa CMK administrada por defecto para cifrar el log group.
  kms_key_arn = null
}

###############################################################################
# Module: notifications
###############################################################################
# Recursos "de cuenta" independientes del environment:
#   - SNS topic para alertas de AWS Budget
#   - Suscripciones email del equipo
#   - AWS Budget ($200/mes, COST)
#
# Se instancia desde live/dev porque el primer `terraform apply` historico fue
# desde dev (Fase 0). Como son recursos de cuenta, el mismo modulo se podria
# instanciar tambien desde live/prod sin duplicar nada (los ARN son unicos a
# nivel de cuenta AWS). Para Fase 2 se podria mover a live/_shared/.
###############################################################################

module "notifications" {
  source = "../../modules/notifications"

  project_name = var.project_name

  # Suscriptores email del equipo. Agregar/quitar requiere un PR + apply.
  # AWS envia email de confirmacion cada vez que se agrega un nuevo suscriptor.
  # Keys son nombres logicos (sin @ ni .) porque Terraform resource addresses
  # para for_each no permiten esos caracteres.
  email_subscriptions = {
    ahincho = "ahincho@unsa.edu.pe"
    ftapara = "ftapara@unsa.edu.pe"
  }

  # Defaults explicitos para documentacion:
  topic_name          = "spark-match-budget-alerts"
  budget_name         = "spark-match-monthly-total"
  budget_limit_amount = 200
}

###############################################################################
# Module: security
###############################################################################
# Capa de seguridad perimetral y de identidad para dev (Fase 1.5):
#   - KMS CMK por entorno (`alias/spark-match-dev-main`) para cifrar
#     SSM/Secrets/S3/data-at-rest. CMK con `enable_key_rotation=true` y
#     `deletion_window_in_days=7` (estricto en dev).
#   - 3 SGs: lambda (egress only), rds (ingress 5432 desde sg-lambda),
#     endpoints (ingress 443 desde sg-lambda). Los 3 con `egress = []` inline
#     para neutralizar el default "egress allow all 0.0.0.0/0" de AWS
#     (IMPROVEMENTS.md A6/SEC-08).
#   - 4 roles OIDC (sam_deploy-dev, bedrock_deploy-dev, lambda_runtime-dev,
#     agentcore_runtime-dev) consumidos por 03-backend y 08-deep-agent desde
#     sus workflows de deploy.
#
# Wire a GitHub:
#   - spark-match-03-backend necesita `AWS_SAM_DEPLOY_ROLE_ARN_DEV` apuntando
#     a module.security.sam_deploy_role_arn.
#   - spark-match-08-deep-agent necesita `AWS_BEDROCK_DEPLOY_ROLE_ARN_DEV`
#     apuntando a module.security.bedrock_deploy_role_arn.
###############################################################################

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment

  vpc_id   = module.networking.vpc_id
  vpc_cidr = var.vpc_cidr

  # 7 dias en dev (mas rapido si hay que borrar el key); 30 en prod.
  kms_deletion_window_in_days = var.kms_deletion_window_in_days

  # Repos GitHub permitidos a asumir los roles OIDC.
  # Se mantienen como variables en live/dev/variables.tf para no hardcodear.
  sam_deploy_github_repos     = var.sam_deploy_github_repos
  bedrock_deploy_github_repos = var.bedrock_deploy_github_repos
}

###############################################################################
# Module: endpoints
###############################################################################
# VPC endpoints para que las Lambdas (cuando esten en VPC) y el contenedor
# FastAPI del agente (en AgentCore) no salgan por NAT para hablar con AWS.
#
# Decisión dev (Opción A — IMPROVEMENTS.md A4/NET-01):
#   - Interface endpoints: DESACTIVADOS en dev (~$7.20/mes por endpoint × 10 =
#     $72/mes). Las Lambdas corren FUERA de VPC por lo que no los necesitan.
#   - Gateway endpoint S3: ACTIVADO (gratis). Lo activamos igual porque si en
#     algun momento una Lambda entra a VPC, ya tendra acceso privado a S3 sin
#     cargo.
#
# El SG que se pasa (`endpoints_security_group_id`) es el mismo que se creo en
# module.security, y permite ingress 443 desde sg-lambda (regla que también se
# creo en module.security via `aws_security_group_rule.endpoints_ingress_from_lambda`).
###############################################################################

module "endpoints" {
  source = "../../modules/endpoints"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  private_route_table_ids = module.networking.private_route_table_ids

  # SG de VPC endpoints (creado en module.security, con ingress 443 desde sg-lambda).
  endpoints_security_group_id = module.security.sg_endpoints_id

  # Decisión dev: solo S3 gateway endpoint (gratis), sin interface endpoints.
  enable_all_endpoints_by_default = var.enable_all_endpoints_by_default
  enable_s3_gateway_endpoint      = var.enable_s3_gateway_endpoint
}