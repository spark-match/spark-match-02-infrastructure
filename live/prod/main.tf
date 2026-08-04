###############################################################################
# Spark Match - Infraestructura productiva
###############################################################################
#
# Fase 0 (completada):
#   - Sin recursos aplicados (cuenta AWS 681526276858 limpia salvo tfstate backend).
#   - State bucket: spark-match-tfstate-prod con versioning + native lockfile.
#
# Fase 1 + Fase 2 (este PR, ADR 0002 — cross-repo config contract):
#   - Wiring completo de los mismos 11 modulos ya aplicados en dev (ver
#     live/dev/main.tf), con decisiones especificas de prod (NAT HA,
#     cobertura completa de VPC endpoints, Multi-AZ en RDS, deletion
#     protection, etc.).
#   - NO se instancia module "notifications": ese modulo crea recursos DE
#     CUENTA (SNS topic + AWS Budget), unicos a nivel de cuenta AWS, y ya
#     fueron creados desde live/dev (ver comentario en ese archivo). Volver
#     a instanciarlo aca colisionaria (nombres duplicados en la misma cuenta).
#
# IMPORTANTE -- este archivo es SOLO CODIGO, aun no aplicado:
#   - No hay ningun `terraform apply` real contra prod todavia.
#   - Promover este PR a `main` (y por tanto disparar terraform-apply-prod.yml
#     via push a main) requiere una decision explicita segun AGENTS.md seccion
#     "Cuando promover dev -> main" (madurez del trabajo o release planeado).
#   - Aunque el codigo llegue a `main`, el apply real esta gateado por
#     aprobacion humana en el GH Environment "production" (required reviewers
#     @spark-match/devops, auto-approve=false) -- ver terraform-apply-prod.yml.
#   - Riesgo conocido documentado en variables.tf: RDS backup_retention_period
#     = 0 (mismo guardrail "Free Tier account" de la cuenta 681526276858 que
#     afecta a dev, ver PR #133). Sin backups automaticos hasta resolver esto.
#
# Politica de cambios:
#   - Cualquier cambio aca requiere PR aprobado por @spark-match/devops.
#   - Apply va por push a rama `main` (post-sync desde dev) o workflow_dispatch.
#   - GH Environment "production" (required reviewers @spark-match/devops,
#     auto-approve=false) requiere aprobacion humana antes del apply real.
###############################################################################

###############################################################################
# Module: networking
###############################################################################
# VPC principal + 2 subnets publicas + 2 subnets privadas (1 por AZ en
# us-east-1a/b). NAT HA activado (1 NAT por AZ): a diferencia de dev, prod
# quiere que la caida de una AZ no deje a las Lambdas sin salida a internet
# generica (ademas de los VPC endpoints). Flow logs activados (REJECT, 90
# dias) para auditoria.
###############################################################################

module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # NAT HA activado en prod (a diferencia de dev). Costo extra ~$64/mes.
  enable_nat_gateway = var.enable_nat_gateway
  enable_nat_ha      = var.enable_nat_ha

  # Flow logs activados en prod para auditoria (REJECT, 90 dias).
  enable_flow_logs        = var.enable_flow_logs
  flow_log_traffic_type   = var.flow_log_traffic_type
  flow_log_retention_days = var.flow_log_retention_days

  # CMK del proyecto (module.kms.kms_key_arn) se usa para cifrar el log group
  # de VPC flow logs. Wireado en dev y prod a la vez el 2026-08-04 para
  # mantener paridad (correccion del leftover de Fase 1 que no se reviso
  # en el wiring de Fase 2, PR #132).
  kms_key_arn = module.kms.kms_key_arn
}

###############################################################################
# Module: oidc-github
###############################################################################
# 4 IAM roles env-scoped (sufijo -prod), asumidos por GitHub Actions y AWS
# services:
#   - spark-match-sam-deploy-prod          (OIDC, spark-match-03-backend)
#   - spark-match-bedrock-agentcore-deploy-prod (OIDC, spark-match-08-deep-agent)
#   - spark-match-lambda-runtime-prod      (Lambda service, spark-match-03-backend)
#   - spark-match-agentcore-runtime-prod   (AgentCore service, spark-match-08-deep-agent)
#
# El OIDC provider en si (`token.actions.githubusercontent.com`) es un
# recurso DE CUENTA (unico, no per-environment) referenciado via data source
# por defecto (create_oidc_provider=false, igual que en dev) -- no se crea
# de nuevo aca, solo se referencia.
#
# Wire a GitHub:
#   - spark-match-03-backend necesita `AWS_SAM_DEPLOY_ROLE_ARN_PROD` apuntando
#     a module.oidc_github.sam_deploy_role_arn.
#   - spark-match-08-deep-agent necesita `AWS_BEDROCK_DEPLOY_ROLE_ARN_PROD`
#     apuntando a module.oidc_github.bedrock_deploy_role_arn.
###############################################################################

module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name = var.project_name
  environment  = var.environment

  sam_deploy_github_repos     = var.sam_deploy_github_repos
  bedrock_deploy_github_repos = var.bedrock_deploy_github_repos
}

###############################################################################
# Module: kms
###############################################################################
# CMK (Customer Managed Key) por entorno (`alias/spark-match-prod-main`) para
# cifrar SSM/Secrets/S3/RDS/DynamoDB/data-at-rest. `deletion_window_in_days=30`
# (maximo AWS, estandar prod -- da tiempo de rollback ante un destroy
# accidental; dev usa 7).
###############################################################################

module "kms" {
  source = "../../modules/kms"

  project_name = var.project_name
  environment  = var.environment

  deletion_window_in_days = var.kms_deletion_window_in_days

  # ARNs de los 4 roles creados por oidc_github module (cross-module reference).
  user_role_arns = [
    module.oidc_github.sam_deploy_role_arn,
    module.oidc_github.bedrock_deploy_role_arn,
    module.oidc_github.lambda_runtime_role_arn,
    module.oidc_github.agentcore_runtime_role_arn,
  ]

  # Dependencia explicita: los 4 IAM roles deben existir antes de la CMK.
  depends_on = [module.oidc_github]
}

###############################################################################
# Module: security-groups
###############################################################################
# 3 SGs cross-cutting: lambda (egress only), rds (ingress 5432 desde
# sg-lambda), endpoints (ingress 443 desde sg-lambda). Los 3 con
# `egress = []` inline para neutralizar el default "egress allow all
# 0.0.0.0/0" de AWS.
###############################################################################

module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  environment  = var.environment

  vpc_id   = module.networking.vpc_id
  vpc_cidr = var.vpc_cidr
}

###############################################################################
# Module: endpoints
###############################################################################
# Decision de arquitectura prod: cobertura completa de interface endpoints
# (SSM, ECR, Logs, Secrets, KMS, STS, Bedrock, events, etc.) + gateway S3,
# para mantener trafico AWS privado (sin atravesar NAT ni internet) incluso
# teniendo NAT disponible. Costo ~$72/mes (10-11 interface endpoints x
# $0.01/h).
#
# `enabled_endpoints` e `interface_endpoint_subnet_ids` NO se pasan a
# proposito (quedan en su default del modulo, [] ambos):
#   - Con enable_all_endpoints_by_default=true, enabled_endpoints se ignora
#     (ver modules/endpoints/main.tf locals.enabled_interface_endpoints).
#   - Con interface_endpoint_subnet_ids=[] el modulo usa automaticamente
#     TODAS las private_subnet_ids (ambas AZs) -- alta disponibilidad, a
#     diferencia de dev que restringe a 1 sola AZ para ahorrar costo.
###############################################################################

module "endpoints" {
  source = "../../modules/endpoints"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  private_route_table_ids = module.networking.private_route_table_ids

  endpoints_security_group_id = module.security_groups.sg_endpoints_id

  enable_all_endpoints_by_default = var.enable_all_endpoints_by_default
  enable_s3_gateway_endpoint      = var.enable_s3_gateway_endpoint
}

###############################################################################
# Module: storage_sam_artifacts
###############################################################################
# Bucket S3 donde `sam deploy` (spark-match-03-backend) sube los artefactos
# de build. `force_destroy=false` en prod (a diferencia de dev): evita
# borrado accidental de artefactos de deploy vigentes.
###############################################################################

module "storage_sam_artifacts" {
  source = "../../modules/storage-sam-artifacts"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn

  force_destroy = var.sam_artifacts_force_destroy
}

###############################################################################
# Module: secrets_bootstrap
###############################################################################
# Secret JWT (HS256 signing key) para que spark-match-03-backend firme/valide
# tokens. `recovery_window_in_days=30` en prod (maximo, protege contra
# borrado accidental; dev usa 0 para iterar rapido).
###############################################################################

module "secrets_bootstrap" {
  source = "../../modules/secrets-bootstrap"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn

  recovery_window_in_days = var.secrets_recovery_window_in_days
}

###############################################################################
# Module: eventbridge_bus
###############################################################################
# Bus de EventBridge custom (`spark-match-events-prod`) para eventos de
# dominio. Archive (30 dias) y DLQ SQS con los defaults del modulo -- sin
# cambios respecto a dev, son valores razonables para ambos entornos.
###############################################################################

module "eventbridge_bus" {
  source = "../../modules/eventbridge-bus"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn
}

###############################################################################
# Module: dynamodb_idempotency
###############################################################################
# Tabla DynamoDB (`spark-match-prod-idempotency`). PAY_PER_REQUEST + point-in-
# time recovery (default true del modulo, sin cambios respecto a dev).
###############################################################################

module "dynamodb_idempotency" {
  source = "../../modules/dynamodb-idempotency"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn
}

###############################################################################
# Module: rds_postgres
###############################################################################
# Instancia RDS PostgreSQL Multi-AZ (`db.t4g.small`, punto de partida
# conservador -- ver comentario en variables.tf). Decisiones prod que
# difieren de dev (todas hardcodeadas aca, no ameritan una variable propia
# por ser decisiones de arquitectura de una sola vez, no algo que se ajuste
# por apply):
#   - multi_az=true: standby en otra AZ con failover automatico.
#   - deletion_protection=true: terraform destroy / aws rds delete-db-instance
#     rechazado sin desactivar esta proteccion primero.
#   - skip_final_snapshot=false: toma un snapshot final antes de cualquier
#     destroy (safety net).
#   - apply_immediately=false: cambios se aplican en la maintenance window,
#     no de inmediato (evita interrupciones en horario productivo).
#   - performance_insights_enabled=true: gratis con 7 dias de retencion
#     incluso en db.t4g.small. Cifrado con la misma CMK del proyecto
#     (performance_insights_kms_key_id, agregado al modulo en este PR -- ver
#     modules/rds-postgres/main.tf, CKV_AWS_354).
#   - enabled_cloudwatch_logs_exports: logs de postgresql y upgrade
#     exportados a CloudWatch para auditoria (costo bajo).
#   - max_allocated_storage_gb=100: autoscaling de storage activado (dev lo
#     deja en 0/desactivado para no salirse del limite free-tier).
#
# rds_backup_retention_period_days=0 (var, NO hardcodeado): mismo guardrail
# de "Free Tier account" que dev, misma cuenta AWS. Ver comentario extenso en
# variables.tf -- riesgo operacional conocido, pendiente de resolver antes
# del primer apply real.
###############################################################################

module "rds_postgres" {
  source = "../../modules/rds-postgres"

  project_name = var.project_name
  environment  = var.environment

  private_subnet_ids    = module.networking.private_subnet_ids
  rds_security_group_id = module.security_groups.sg_rds_id
  kms_key_arn           = module.kms.kms_key_arn

  instance_class = var.db_instance_class
  multi_az       = true

  max_allocated_storage_gb = 100

  deletion_protection = true
  skip_final_snapshot = false
  apply_immediately   = false

  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  secret_recovery_window_in_days = var.secrets_recovery_window_in_days
  backup_retention_period_days   = var.rds_backup_retention_period_days
}

###############################################################################
# Module: ssm_bootstrap
###############################################################################
# 8 parametros SSM bajo /spark-match/prod/config/* -- mismo contrato
# cross-repo que dev (ver ADR 0002), aislado por prefijo de environment en la
# misma cuenta AWS.
###############################################################################

module "ssm_bootstrap" {
  source = "../../modules/ssm-bootstrap"

  project_name = var.project_name
  environment  = var.environment

  eventbridge_bus_arn = module.eventbridge_bus.bus_arn
  db_secret_arn       = module.rds_postgres.db_credentials_secret_arn
  jwt_secret_arn      = module.secrets_bootstrap.jwt_secret_arn
  db_connection_url   = module.rds_postgres.connection_url

  idempotency_table_name = module.dynamodb_idempotency.table_name
  cors_allowed_origins   = var.cors_allowed_origins

  # VpcConfig para las Lambdas del backend (ADR 0002 seccion 5).
  private_subnet_ids       = module.networking.private_subnet_ids
  lambda_security_group_id = module.security_groups.sg_lambda_id

  kms_key_arn = module.kms.kms_key_arn
}
