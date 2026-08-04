###############################################################################
# Spark Match - Infraestructura dev
###############################################################################
#
# Fase 0 (completada):
#   - Sin recursos aplicados (cuenta AWS 681526276858 limpia salvo tfstate backend).
#   - State bucket: spark-match-tfstate-dev con versioning + native lockfile.
#
# Fase 1 (completada):
#   - module "networking"      -> VPC 10.10.0.0/16, NAT OFF, 1 subnet publica + 1 privada por AZ
#   - module "security_groups" -> SGs lambda/rds/endpoints
#   - module "kms"             -> CMK por entorno
#   - module "endpoints"       -> S3 gateway + interface endpoints (secretsmanager, events)
#   - module "oidc_github"     -> OIDC provider + 4 IAM roles
#
# Fase 2 (activa, ADR 0002 — cross-repo config contract):
#   - module "storage_sam_artifacts"  -> S3 bucket de artefactos SAM
#   - module "secrets_bootstrap"      -> Secrets Manager (JWT signing key)
#   - module "eventbridge_bus"        -> EventBridge bus custom + archive + DLQ
#   - module "dynamodb_idempotency"   -> Tabla DynamoDB de idempotencia
#   - module "rds_postgres"           -> RDS PostgreSQL Single-AZ + secret de credenciales
#   - module "ssm_bootstrap"          -> 8 parametros SSM (contrato con 03-backend)
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
# NAT gateway desactivado en dev: las Lambdas del backend corren DENTRO de la
# VPC (subnet privada, para llegar a RDS por TCP 5432 -- ver ADR 0002 seccion 4),
# pero sin necesidad de salida generica a internet. Las unicas llamadas SDK
# salientes (Secrets Manager, EventBridge PutEvents) se resuelven con 2
# interface endpoints en 1 sola AZ (module.endpoints), no con NAT.
# Flow logs desactivados en dev para minimizar costo (default false).
#
# Outputs consumidos por modules/networking y modules/endpoints (Fase 1.5):
#   - vpc_id, public_subnet_ids, private_subnet_ids, private_route_table_ids
###############################################################################

module "networking" {
  source = "../../modules/networking"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # NAT desactivado en dev: ver comentario del modulo arriba (ADR 0002 §4).
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
# Module: oidc-github
###############################################################################
# OIDC provider (data source por defecto, recurso opt-in via create_oidc_provider)
# + 4 IAM roles asumidos por GitHub Actions y AWS services:
#   - spark-match-sam-deploy-dev          (OIDC, spark-match-03-backend)
#   - spark-match-bedrock-agentcore-deploy-dev (OIDC, spark-match-08-deep-agent)
#   - spark-match-lambda-runtime-dev      (Lambda service, spark-match-03-backend)
#   - spark-match-agentcore-runtime-dev   (AgentCore service, spark-match-08-deep-agent)
#
# Extraido de modules/security-groups en PR4a (Sprint 1). Patron copiado de
# orion-infrastructure/modules/oidc-github/.
#
# Wire a GitHub:
#   - spark-match-03-backend necesita `AWS_SAM_DEPLOY_ROLE_ARN_DEV` apuntando
#     a module.oidc_github.sam_deploy_role_arn.
#   - spark-match-08-deep-agent necesita `AWS_BEDROCK_DEPLOY_ROLE_ARN_DEV`
#     apuntando a module.oidc_github.bedrock_deploy_role_arn.
###############################################################################

module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name = var.project_name
  environment  = var.environment

  # Repos GitHub permitidos a asumir los roles OIDC.
  # Se mantienen como variables en live/dev/variables.tf para no hardcodear.
  sam_deploy_github_repos     = var.sam_deploy_github_repos
  bedrock_deploy_github_repos = var.bedrock_deploy_github_repos
}

###############################################################################
# Module: kms
###############################################################################
# CMK (Customer Managed Key) por entorno (`alias/spark-match-dev-main`) para
# cifrar SSM/Secrets/S3/data-at-rest. CMK con `enable_key_rotation=true` y
# `deletion_window_in_days=7` (estricto en dev).
#
# PR4b (Sprint 1): extraido de modules/security-groups. Recibe `user_role_arns` cross-module
# desde module.oidc_github.*_role_arn para que la CMK key policy pueda referenciar
# los ARNs de los 4 roles.
###############################################################################

module "kms" {
  source = "../../modules/kms"

  project_name = var.project_name
  environment  = var.environment

  # 7 dias en dev (mas rapido si hay que borrar el key); 30 en prod.
  deletion_window_in_days = var.kms_deletion_window_in_days

  # ARNs de los 4 roles creados por oidc_github module (cross-module reference).
  # KMS exige que los principals existan al validar la policy, por lo que Terraform
  # resuelve automaticamente el orden de creacion (oidc_github primero, kms despues).
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
# 3 SGs cross-cutting: lambda (egress only), rds (ingress 5432 desde sg-lambda),
# endpoints (ingress 443 desde sg-lambda). Los 3 con `egress = []` inline para
# neutralizar el default "egress allow all 0.0.0.0/0" de AWS
# (IMPROVEMENTS.md A6/SEC-08).
#
# PR4c (Sprint 1): extraido de modules/security-groups.
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
# VPC endpoints para que las Lambdas del backend (dentro de VPC, ver ADR 0002
# §4) no salgan por NAT para hablar con AWS.
#
# Decision dev (ADR 0002 §4):
#   - Interface endpoints: solo `secretsmanager` (leer credenciales frescas de
#     RDS) y `events` (PutEvents a EventBridge). Desplegados en 1 sola AZ (no
#     las 2) para reducir costo: ~$14.60/mes (2 endpoints x 1 AZ) en vez de
#     ~$72/mes (10 endpoints x 2 AZ, catalogo completo).
#   - Gateway endpoint S3: ACTIVADO (gratis).
#   - CloudWatch Logs y X-Ray no requieren VPC endpoint (viajan por el plano
#     de control de Lambda, no por la ENI de la funcion).
#   - `ssm` NO esta en la lista: el runtime del backend lee env vars
#     inyectadas en deploy-time via `{{resolve:ssm:}}`, no relee SSM (ADR 0002 §3).
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

  # SG de VPC endpoints (creado en module.security_groups, con ingress 443 desde sg-lambda).
  endpoints_security_group_id = module.security_groups.sg_endpoints_id

  # Decision dev (ADR 0002 §4): solo secretsmanager + events, en 1 AZ.
  enable_all_endpoints_by_default = var.enable_all_endpoints_by_default
  enabled_endpoints               = var.enabled_endpoints
  enable_s3_gateway_endpoint      = var.enable_s3_gateway_endpoint

  # 1 sola AZ (la primera subnet privada) en vez de las 2 -- reduce costo a
  # la mitad (~$7.20/mes por endpoint por AZ evitada).
  interface_endpoint_subnet_ids = slice(module.networking.private_subnet_ids, 0, 1)
}

###############################################################################
# Module: storage_sam_artifacts
###############################################################################
# Bucket S3 donde `sam deploy` (spark-match-03-backend) sube los artefactos
# de build (zips de Lambda, plantillas empaquetadas). Cifrado con la CMK del
# proyecto, versionado, con bucket de access logs dedicado (ver Sonar S6249/
# S6258 en PR #130).
###############################################################################

module "storage_sam_artifacts" {
  source = "../../modules/storage-sam-artifacts"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn

  # true en dev: permite `terraform destroy` sin vaciar el bucket a mano
  # mientras iteramos (los artefactos de build son recreables, no criticos).
  force_destroy = var.sam_artifacts_force_destroy
}

###############################################################################
# Module: secrets_bootstrap
###############################################################################
# Secret JWT (HS256 signing key, 48 bytes aleatorios en base64) para que
# spark-match-03-backend firme/valide access y refresh tokens. Unico secret
# de este modulo -- el secret de credenciales de RDS vive en modules/rds-postgres
# (ver ADR 0002 seccion 2, decision de ownership).
###############################################################################

module "secrets_bootstrap" {
  source = "../../modules/secrets-bootstrap"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn

  # 0 en dev: permite recrear el secret sin esperar el recovery window si se
  # necesita rotar/destruir durante la iteracion (ver descripcion de la variable).
  recovery_window_in_days = var.secrets_recovery_window_in_days
}

###############################################################################
# Module: eventbridge_bus
###############################################################################
# Bus de EventBridge custom (`spark-match-events-{env}`) para eventos de
# dominio (ej: MatchCreated, ApplicationSubmitted). Incluye archive (30 dias)
# y DLQ SQS para target failures de las reglas que consuman este bus.
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
# Tabla DynamoDB (`spark-match-{env}-idempotency`) usada por el backend para
# evitar procesar el mismo evento/request 2 veces (patron idempotency key +
# TTL). PAY_PER_REQUEST: sin costo fijo, solo por uso.
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
# Instancia RDS PostgreSQL Single-AZ (`db.t4g.micro`, free-tier los primeros
# 12 meses de la cuenta). Decision explicita: RDS estandar, NO Aurora
# Serverless v2 (Aurora minimo cuesta ~$43/mes incluso idle, ver PR #131).
# El secret de credenciales (`spark-match-{env}-db-credentials`) se crea
# dentro de este modulo -- ver ADR 0002 seccion 2 para el razonamiento.
###############################################################################

module "rds_postgres" {
  source = "../../modules/rds-postgres"

  project_name = var.project_name
  environment  = var.environment

  private_subnet_ids    = module.networking.private_subnet_ids
  rds_security_group_id = module.security_groups.sg_rds_id
  kms_key_arn           = module.kms.kms_key_arn

  # 0 en dev: permite recrear el secret de credenciales sin esperar el
  # recovery window (mismo razonamiento que module.secrets_bootstrap).
  secret_recovery_window_in_days = var.secrets_recovery_window_in_days
}

###############################################################################
# Module: ssm_bootstrap
###############################################################################
# 8 parametros SSM bajo /spark-match/dev/config/* que forman el contrato
# cross-repo con spark-match-03-backend (ver ADR 0002 completo). Este modulo
# no calcula nada: solo expone los outputs de los modulos anteriores en las
# rutas que el template SAM del backend resuelve via `{{resolve:ssm:}}`.
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