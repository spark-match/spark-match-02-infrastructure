###############################################################################
# Outputs del entorno prod
###############################################################################
#
# Convenciones para los nombres de outputs:
#   - *_id      -> identificador del recurso (vpc-xxx, sg-xxx)
#   - *_arn     -> ARN completo
#   - *_name    -> nombre logico del recurso (bucket, tabla, bus)
#
# La mayoria de estos valores tambien se resuelven automaticamente por
# spark-match-03-backend via SSM (`{{resolve:ssm:/spark-match/prod/config/*}}`,
# ver module.ssm_bootstrap y docs/adr/0002-cross-repo-config-contract-ssm-secrets.md).
# Se exponen tambien aca para debug rapido (`terraform output`) sin tener que
# hacer `aws ssm get-parameter` a mano, y para wiring manual de los 4 IAM
# roles OIDC en GitHub Actions (spark-match-03-backend, spark-match-08-deep-agent).
#
# No se expone ningun valor sensible (passwords, connection strings) en texto
# plano: `rds_postgres.connection_url` NO se re-expone aca (ya vive cifrado en
# el SSM SecureString /spark-match/prod/config/db-connection-url).
###############################################################################

###############################################################################
# Networking
###############################################################################

output "vpc_id" {
  description = "ID de la VPC prod."
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR de la VPC prod."
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las subnets publicas prod."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas prod (donde corren las Lambdas del backend)."
  value       = module.networking.private_subnet_ids
}

###############################################################################
# Security groups
###############################################################################

output "sg_lambda_id" {
  description = "ID del security group para Lambdas. Necesario para el VpcConfig de spark-match-03-backend (tambien expuesto via SSM)."
  value       = module.security_groups.sg_lambda_id
}

output "sg_rds_id" {
  description = "ID del security group para RDS."
  value       = module.security_groups.sg_rds_id
}

output "sg_endpoints_id" {
  description = "ID del security group para VPC endpoints."
  value       = module.security_groups.sg_endpoints_id
}

###############################################################################
# KMS
###############################################################################

output "kms_key_arn" {
  description = "ARN de la CMK prod (cifra SSM SecureString, Secrets Manager, S3, RDS, DynamoDB, SQS)."
  value       = module.kms.kms_key_arn
}

output "kms_alias_name" {
  description = "Alias de la CMK prod."
  value       = module.kms.kms_alias_name
}

###############################################################################
# OIDC / IAM roles (wiring manual en GitHub Actions de otros repos)
###############################################################################

output "sam_deploy_role_arn" {
  description = "ARN del role asumido por GitHub Actions de spark-match-03-backend para `sam deploy`. Wire a AWS_SAM_DEPLOY_ROLE_ARN_PROD."
  value       = module.oidc_github.sam_deploy_role_arn
}

output "bedrock_deploy_role_arn" {
  description = "ARN del role asumido por GitHub Actions de spark-match-08-deep-agent. Wire a AWS_BEDROCK_DEPLOY_ROLE_ARN_PROD."
  value       = module.oidc_github.bedrock_deploy_role_arn
}

output "lambda_runtime_role_arn" {
  description = "ARN del role de ejecucion de las Lambdas del backend (service role, no OIDC)."
  value       = module.oidc_github.lambda_runtime_role_arn
}

output "agentcore_runtime_role_arn" {
  description = "ARN del role de ejecucion del contenedor AgentCore (service role, no OIDC)."
  value       = module.oidc_github.agentcore_runtime_role_arn
}

###############################################################################
# Storage (SAM artifacts)
###############################################################################

output "sam_artifacts_bucket_name" {
  description = "Nombre del bucket S3 de artefactos SAM. Wire a samconfig.toml (s3_bucket) en spark-match-03-backend."
  value       = module.storage_sam_artifacts.bucket_name
}

output "sam_artifacts_bucket_arn" {
  description = "ARN del bucket S3 de artefactos SAM."
  value       = module.storage_sam_artifacts.bucket_arn
}

###############################################################################
# Secrets
###############################################################################

output "jwt_secret_arn" {
  description = "ARN del secret JWT (identificador, no secreto en si mismo)."
  value       = module.secrets_bootstrap.jwt_secret_arn
}

output "db_credentials_secret_arn" {
  description = "ARN del secret de credenciales RDS (identificador, no secreto en si mismo)."
  value       = module.rds_postgres.db_credentials_secret_arn
}

###############################################################################
# EventBridge
###############################################################################

output "eventbridge_bus_name" {
  description = "Nombre del bus de EventBridge custom prod."
  value       = module.eventbridge_bus.bus_name
}

output "eventbridge_bus_arn" {
  description = "ARN del bus de EventBridge custom prod."
  value       = module.eventbridge_bus.bus_arn
}

###############################################################################
# DynamoDB
###############################################################################

output "idempotency_table_name" {
  description = "Nombre de la tabla DynamoDB de idempotencia prod."
  value       = module.dynamodb_idempotency.table_name
}

###############################################################################
# RDS
###############################################################################

output "db_instance_id" {
  description = "Identifier de la instancia RDS prod."
  value       = module.rds_postgres.db_instance_id
}

output "db_address" {
  description = "Endpoint (hostname) de la instancia RDS prod, sin el puerto."
  value       = module.rds_postgres.db_address
}

output "db_port" {
  description = "Puerto de la instancia RDS prod (5432)."
  value       = module.rds_postgres.db_port
}

output "db_name" {
  description = "Nombre de la base de datos inicial prod."
  value       = module.rds_postgres.db_name
}

###############################################################################
# SSM (contrato cross-repo, ADR 0002)
###############################################################################

output "ssm_config_prefix" {
  description = "Prefijo comun de los parametros SSM del backend (/spark-match/prod/config)."
  value       = module.ssm_bootstrap.config_prefix
}

output "ssm_parameter_names" {
  description = "Map con los 8 nombres (paths) de los parametros SSM creados para spark-match-03-backend."
  value       = module.ssm_bootstrap.parameter_names
}
