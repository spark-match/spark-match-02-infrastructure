###############################################################################
# Outputs del entorno dev
###############################################################################
#
# Convenciones para los nombres de outputs:
#   - *_id      -> identificador del recurso (vpc-xxx, sg-xxx)
#   - *_arn     -> ARN completo
#   - *_name    -> nombre logico del recurso (bucket, tabla, bus)
#
# La mayoria de estos valores tambien se resuelven automaticamente por
# spark-match-03-backend via SSM (`{{resolve:ssm:/spark-match/dev/config/*}}`,
# ver module.ssm_bootstrap y docs/adr/0002-cross-repo-config-contract-ssm-secrets.md).
# Se exponen tambien aca para debug rapido (`terraform output`) sin tener que
# hacer `aws ssm get-parameter` a mano, y para wiring manual de los 4 IAM
# roles OIDC en GitHub Actions (spark-match-03-backend, spark-match-08-deep-agent).
#
# No se expone ningun valor sensible (passwords, connection strings) en texto
# plano: `rds_postgres.connection_url` NO se re-expone aca (ya vive cifrado en
# el SSM SecureString /spark-match/dev/config/db-connection-url).
###############################################################################

###############################################################################
# Networking
###############################################################################

output "vpc_id" {
  description = "ID de la VPC dev."
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR de la VPC dev."
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las subnets publicas dev."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas dev (donde corren las Lambdas del backend)."
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
  description = "ARN de la CMK dev (cifra SSM SecureString, Secrets Manager, S3, RDS, DynamoDB, SQS)."
  value       = module.kms.kms_key_arn
}

output "kms_alias_name" {
  description = "Alias de la CMK dev."
  value       = module.kms.kms_alias_name
}

###############################################################################
# OIDC / IAM roles (wiring manual en GitHub Actions de otros repos)
###############################################################################

output "sam_deploy_role_arn" {
  description = "ARN del role asumido por GitHub Actions de spark-match-03-backend para `sam deploy`. Wire a AWS_SAM_DEPLOY_ROLE_ARN_DEV."
  value       = module.oidc_github.sam_deploy_role_arn
}

output "bedrock_deploy_role_arn" {
  description = "ARN del role asumido por GitHub Actions de spark-match-08-deep-agent. Wire a AWS_BEDROCK_DEPLOY_ROLE_ARN_DEV."
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
  description = "Nombre del bus de EventBridge custom dev."
  value       = module.eventbridge_bus.bus_name
}

output "eventbridge_bus_arn" {
  description = "ARN del bus de EventBridge custom dev."
  value       = module.eventbridge_bus.bus_arn
}

###############################################################################
# DynamoDB
###############################################################################

output "idempotency_table_name" {
  description = "Nombre de la tabla DynamoDB de idempotencia dev."
  value       = module.dynamodb_idempotency.table_name
}

###############################################################################
# RDS
###############################################################################

output "db_instance_id" {
  description = "Identifier de la instancia RDS dev."
  value       = module.rds_postgres.db_instance_id
}

output "db_address" {
  description = "Endpoint (hostname) de la instancia RDS dev, sin el puerto."
  value       = module.rds_postgres.db_address
}

output "db_port" {
  description = "Puerto de la instancia RDS dev (5432)."
  value       = module.rds_postgres.db_port
}

output "db_name" {
  description = "Nombre de la base de datos inicial dev."
  value       = module.rds_postgres.db_name
}

###############################################################################
# SSM (contrato cross-repo, ADR 0002)
###############################################################################

output "ssm_config_prefix" {
  description = "Prefijo comun de los parametros SSM del backend (/spark-match/dev/config)."
  value       = module.ssm_bootstrap.config_prefix
}

output "ssm_parameter_names" {
  description = "Map con los 8 nombres (paths) de los parametros SSM creados para spark-match-03-backend."
  value       = module.ssm_bootstrap.parameter_names
}

###############################################################################
# Frontend hosting (S3 + CloudFront + OAC)
###############################################################################

output "frontend_bucket_name" {
  description = "Nombre del bucket S3 que almacena los assets del frontend. Wire a 04-frontend config (S3_BUCKET)."
  value       = module.frontend_hosting.frontend_bucket_name
}

output "frontend_bucket_arn" {
  description = "ARN del bucket S3 del frontend."
  value       = module.frontend_hosting.frontend_bucket_arn
}

output "frontend_bucket_regional_domain_name" {
  description = "Domain name regional del bucket S3 (para endpoint regional en scripts de deploy)."
  value       = module.frontend_hosting.frontend_bucket_regional_domain_name
}

output "frontend_distribution_id" {
  description = "ID de la distribucion CloudFront del frontend. Wire a 04-frontend config (CLOUDFRONT_DISTRIBUTION_ID)."
  value       = module.frontend_hosting.frontend_distribution_id
}

output "frontend_distribution_domain_name" {
  description = "Default domain name de la distribucion (*.cloudfront.net)."
  value       = module.frontend_hosting.frontend_distribution_domain_name
}

output "frontend_distribution_arn" {
  description = "ARN de la distribucion CloudFront del frontend."
  value       = module.frontend_hosting.frontend_distribution_arn
}

output "frontend_deploy_role_arn" {
  description = "ARN del role OIDC asumido por spark-match-04-frontend para deploy. Wire a GitHub Actions secret AWS_FRONTEND_DEPLOY_ROLE_ARN_DEV."
  value       = module.oidc_frontend.deploy_role_arn
}

###############################################################################
# deep-agent (modules/ecr + modules/agent-service)
###############################################################################
# Todos usan one(...) porque los modulos llevan count (var.enable_agent_service):
# devuelven null cuando el agente esta apagado, en vez de romper el output.

output "agent_ecr_repository_name" {
  description = "Nombre del repositorio ECR del agente. Wire a spark-match-08-deep-agent como repo-level var ECR_REPOSITORY_DEV."
  value       = one(module.ecr[*].repository_name)
}

output "agent_ecr_repository_url" {
  description = "URL del repositorio ECR del agente (base del tag de imagen en el push)."
  value       = one(module.ecr[*].repository_url)
}

output "agent_cluster_name" {
  description = "Nombre del cluster ECS del agente. Input `cluster-name` de la receta reusable-ecs-deploy.yml."
  value       = one(module.agent_service[*].cluster_name)
}

output "agent_service_name" {
  description = "Nombre del servicio ECS del agente. Input `service-name` de la receta reusable-ecs-deploy.yml."
  value       = one(module.agent_service[*].service_name)
}

output "agent_container_name" {
  description = "Nombre del contenedor dentro de la task definition. Input `container-name` de la receta reusable-ecs-deploy.yml."
  value       = one(module.agent_service[*].container_name)
}

output "agent_task_definition_family" {
  description = "Family de la task definition del agente."
  value       = one(module.agent_service[*].task_definition_family)
}

output "agent_execution_role_arn" {
  description = "ARN del execution role de la task del agente (spark-match-agentcore-exec-dev)."
  value       = one(module.agent_service[*].execution_role_arn)
}

output "agent_endpoint_url" {
  description = "URL base del agente (http://{alb-dns}). Mismo valor que /spark-match/dev/config/agent-endpoint-url."
  value       = one(module.agent_service[*].agent_endpoint_url)
}

output "agent_log_group_name" {
  description = "Log group donde el contenedor del agente escribe stdout/stderr."
  value       = one(module.agent_service[*].log_group_name)
}

output "agent_sg_id" {
  description = "ID del SG de las tasks del agente."
  value       = one(module.agent_service[*].sg_agent_id)
}
