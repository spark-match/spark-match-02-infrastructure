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
#   - module "database"     -> RDS Aurora PostgreSQL Serverless v2 + pgvector
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