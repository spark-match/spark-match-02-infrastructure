###############################################################################
# Spark Match - Infraestructura productiva
###############################################################################
#
# Fase 0 (actual):
#   - Sin recursos aplicados (cuenta AWS 681526276858 limpia salvo tfstate backend).
#
# Fase 1 (proxima):
#   - module "security"   -> IAM base roles, security groups, KMS keys
#   - module "networking" -> VPC + subnets publicas/privadas + NAT + endpoints
#
# Fases futuras:
#   - module "database"     -> RDS Aurora PostgreSQL Serverless v2 (sin pgvector; vector store en otro proveedor)
#   - module "storage"      -> S3 buckets definitivos
#   - module "events"       -> EventBridge bus custom + archive + DLQ
#   - module "secrets"      -> Secrets Manager (JWT, DB credentials)
#   - module "monitoring"   -> CloudWatch + SNS
#   - module "bedrock"      -> IAM para Bedrock + ECR repo del agente
#
