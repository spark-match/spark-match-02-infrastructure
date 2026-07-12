###############################################################################
# Spark Match - Infraestructura dev
###############################################################################
#
# Fase 0 (actual):
#   - Sin recursos aplicados (cuenta AWS 681526276858 limpia salvo tfstate backend).
#   - State bucket: spark-match-tfstate-dev (a crear via bootstrap-backend.sh).
#
# Fase 1 (proxima):
#   - module "networking" -> VPC 10.10.0.0/16, NAT OFF, 1 subnet publica + 1 privada por AZ
#   - module "security"   -> IAM roles *-dev, KMS CMK dev, SGs
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
