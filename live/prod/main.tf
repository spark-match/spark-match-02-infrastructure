###############################################################################
# Spark Match - Infraestructura productiva
###############################################################################
#
# Fase 0 (completada):
#   - Sin recursos aplicados (cuenta AWS 681526276858 limpia salvo tfstate backend).
#   - State bucket: spark-match-tfstate-prod con versioning + native lockfile.
#
# Fase 1 + Fase 2 (este PR, ADR 0002 â€” cross-repo config contract):
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
#   - spark-match-bedrock-agentcore-deploy-prod (OIDC, spark-match-07-deep-agent)
#   - spark-match-lambda-runtime-prod      (Lambda service, spark-match-03-backend)
#   - spark-match-agentcore-runtime-prod   (AgentCore service, spark-match-07-deep-agent)
#
# El OIDC provider en si (`token.actions.githubusercontent.com`) es un
# recurso DE CUENTA (unico, no per-environment) referenciado via data source
# por defecto (create_oidc_provider=false, igual que en dev) -- no se crea
# de nuevo aca, solo se referencia.
#
# Wire a GitHub:
#   - spark-match-03-backend necesita `AWS_SAM_DEPLOY_ROLE_ARN_PROD` apuntando
#     a module.oidc_github.sam_deploy_role_arn.
#   - spark-match-07-deep-agent necesita `AWS_BEDROCK_DEPLOY_ROLE_ARN_PROD`
#     apuntando a module.oidc_github.bedrock_deploy_role_arn.
###############################################################################

module "oidc_github" {
  source = "../../modules/oidc-github"

  project_name = var.project_name
  environment  = var.environment

  # El GH Environment real se llama "production" (ver `gh api
  # repos/spark-match/*/environments`), no "prod" -- `environment` arriba
  # solo nombra los recursos AWS. Sin este override, el sub claim
  # `environment:production` que emite GitHub no matchea el trust policy
  # (que usaria `environment:prod`) y AssumeRoleWithWebIdentity es rechazado.
  github_environment_name = "production"

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
# Decision de arquitectura prod (checkpoint de costos 2026-08-04): con NAT
# presente (module "networking" abajo, enable_nat_ha=false pero NAT si esta
# ON), solo los servicios que las Lambdas/el agente llaman con volumen alto
# o baja tolerancia a latencia de NAT necesitan interface endpoint dedicado.
# Los 11 endpoints x 2 AZ (22 ENI) costaban ~$160.60/mes; con
# enabled_endpoints explicito (4 servicios) + interface_endpoint_subnet_ids
# a 1 sola AZ (mismo patron que dev) el costo baja a ~$29.20/mes.
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
  enabled_endpoints               = var.enabled_endpoints
  enable_s3_gateway_endpoint      = var.enable_s3_gateway_endpoint

  # 1 sola AZ (la primera subnet privada), mismo recorte que dev -- reduce
  # el costo a la mitad (~$7.30/mes por endpoint por AZ evitada).
  interface_endpoint_subnet_ids = slice(module.networking.private_subnet_ids, 0, 1)
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
#   - multi_az=false (checkpoint de costos 2026-08-04): sin standby en otra
#     AZ. Ahorra ~$25.66/mes (computo + storage duplicado). Coherente con
#     rds_backup_retention_period_days=0 abajo: sin PITR, Multi-AZ ya daba
#     HA a medias pagando el costo completo. Revertir a true cuando se
#     resuelva el guardrail de backups de la cuenta.
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
  multi_az       = false

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

###############################################################################
# Module: reports_storage
###############################################################################
# Bucket privado donde viven los informes de orientacion (ADR-019 de
# spark-match-03-backend). El agente sube el JSON y el PDF; el backend guarda
# en su BD solo bucket + key + version_id y sirve el contenido por su API.
#
# Sin CloudFront a proposito: contenido privado que lee una sola persona, nada
# que cachear, y ponerlo delante obligaria a signed URLs con su key pair y su
# rotacion. No confundir con module.frontend_hosting, que si lleva CloudFront
# porque sirve un sitio estatico publico.
#
# Aqui el contenido son perfiles vocacionales de estudiantes reales, asi que
# force_destroy va en false sin discusion.
###############################################################################

module "reports_storage" {
  source = "../../modules/reports-storage"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn   = module.kms.kms_key_arn
  force_destroy = false

  access_logs_retention_days = var.reports_access_logs_retention_days
}

module "ssm_bootstrap" {
  source = "../../modules/ssm-bootstrap"

  project_name = var.project_name
  environment  = var.environment

  eventbridge_bus_arn = module.eventbridge_bus.bus_arn
  db_secret_arn       = module.rds_postgres.db_credentials_secret_arn
  jwt_secret_arn      = module.secrets_bootstrap.jwt_secret_arn
  db_connection_url   = module.rds_postgres.connection_url

  idempotency_table_name = module.dynamodb_idempotency.table_name

  # Derivado del output de CloudFront, no de una variable. Antes esto era
  # `var.cors_allowed_origins`, cuyo valor en terraform.tfvars era un
  # placeholder invalido con una marca de pendiente que pedia reemplazarlo por
  # el dominio real antes del primer apply. Ese pendiente no se podia cumplir:
  # el dominio ES el de la distribucion CloudFront, que no existe hasta que se
  # aplique este mismo fichero. Huevo y gallina.
  #
  # module "agent_service" (mas abajo) ya lo hacia bien; solo este se habia
  # quedado con el placeholder, y de aqui pasaba al parametro SSM
  # /spark-match/prod/cors-allowed-origins que leen las Lambdas del backend.
  #
  # OJO con el formato: NO se puede copiar el `jsonencode([...])` del agente.
  # Los dos consumidores esperan cosas distintas -- el agente un array JSON en
  # SPARK_CORS_ORIGINS, y ssm_bootstrap una cadena separada por comas (en dev
  # recibe "*"). Aqui va string plano.
  cors_allowed_origins = "https://${module.frontend_hosting.frontend_distribution_domain_name}"

  # VpcConfig para las Lambdas del backend (ADR 0002 seccion 5).
  private_subnet_ids       = module.networking.private_subnet_ids
  lambda_security_group_id = module.security_groups.sg_lambda_id

  # Informes de orientacion (ADR-019). Los dos numeros se publican en SSM para
  # poder ajustarlos sin redesplegar ni el backend ni el agente.
  reports_bucket_name              = module.reports_storage.bucket_name
  reports_max_per_user_per_day     = var.reports_max_per_user_per_day
  reports_min_profile_completeness = var.reports_min_profile_completeness

  kms_key_arn = module.kms.kms_key_arn
}

###############################################################################
# Module: frontend_hosting
###############################################################################
# Bucket S3 + CloudFront + OAC para servir el build estatico de
# spark-match-04-frontend en prod. force_destroy=false (a diferencia de
# dev) para no borrar accidentalmente los assets de deploy vigentes.
###############################################################################

module "frontend_hosting" {
  source = "../../modules/frontend-hosting"

  project_name = var.project_name
  environment  = var.environment

  force_destroy                      = var.frontend_force_destroy
  access_logs_retention_days         = var.frontend_access_logs_retention_days
  noncurrent_version_expiration_days = var.frontend_noncurrent_version_expiration_days
}

###############################################################################
# Module: oidc_frontend
###############################################################################
# Role OIDC prod (spark-match-frontend-deploy-prod) asumido por 04-frontend
# en CI contra refs/heads/main + environment:production.
###############################################################################

module "oidc_frontend" {
  source = "../../modules/oidc-frontend"

  project_name = var.project_name
  environment  = var.environment

  bucket_arn             = module.frontend_hosting.frontend_bucket_arn
  access_logs_bucket_arn = module.frontend_hosting.access_logs_bucket_arn
  distribution_arn       = module.frontend_hosting.frontend_distribution_arn
}

###############################################################################
# Module: ecr
###############################################################################
# Repositorio `spark-match-agent-advisor-prod`. El nombre importa: cae dentro
# del allowlist IAM `spark-match-agent-*-prod` de la policy
# spark-match-bedrock-agentcore-deploy. El valor que hoy tiene configurado
# spark-match-07-deep-agent (`spark-match-agent-advisor-production`) NO
# matchea ese patron -- se corrige en el PR-DA2 de ese repo.
###############################################################################

module "ecr" {
  count = var.enable_agent_service ? 1 : 0

  source = "../../modules/ecr"

  project_name = var.project_name
  environment  = var.environment

  kms_key_arn = module.kms.kms_key_arn

  # false en prod: evita que un `terraform destroy` borre la imagen que esta
  # corriendo en el servicio.
  force_delete = var.agent_ecr_force_delete
}

###############################################################################
# Module: agent_service
###############################################################################
# Cluster ECS + task definition Fargate ARM64 + servicio detras de un ALB
# publico para spark-match-07-deep-agent.
#
# Decision prod (a diferencia de dev): las tasks corren en las subnets
# PRIVADAS sin IP publica. El egress a ECR/Bedrock/Secrets sale por el NAT
# unico (enable_nat_ha=false, checkpoint de costos 2026-08-04) y por los 4
# interface endpoints habilitados. Solo el ALB vive en las subnets publicas.
#
# Costo estimado: Fargate 0.5 vCPU / 1 GiB ~$18/mes + ALB ~$17.50/mes + ECR
# ~$0.30/mes. Sumado a los ~$101/mes del resto de prod queda en ~$137/mes,
# bajo el budget de $200/mes de la cuenta.
###############################################################################

module "agent_service" {
  count = var.enable_agent_service ? 1 : 0

  source = "../../modules/agent-service"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id   = module.networking.vpc_id
  vpc_cidr = var.vpc_cidr

  # ALB en publicas (>= 2 AZs, requisito de ELB); tasks en privadas.
  alb_subnet_ids     = module.networking.public_subnet_ids
  service_subnet_ids = module.networking.private_subnet_ids
  assign_public_ip   = false

  # El modulo agrega la rule de ingress 5432 sobre este SG para que el
  # checkpointer de LangGraph (schema `agent`) llegue a RDS.
  rds_security_group_id           = module.security_groups.sg_rds_id
  vpc_endpoints_security_group_id = module.security_groups.sg_endpoints_id

  # Task role: los permisos que usa el codigo del agente en runtime (Bedrock,
  # Secrets Manager, SSM). El execution role lo crea el propio modulo.
  agentcore_runtime_role_arn = module.oidc_github.agentcore_runtime_role_arn

  # `latest`, no `bootstrap`: el pipeline de spark-match-07-deep-agent publica
  # con `image-tags-input: 'latest,__GITHUB_SHA_SHORT__,__GITHUB_REF_NAME__'`,
  # o sea NUNCA existe un tag `bootstrap`. Apuntar ahi dejaba al servicio en
  # CannotPullContainerError indefinidamente (comprobado en dev).
  container_image    = "${module.ecr[0].repository_url}:latest"
  ecr_repository_url = module.ecr[0].repository_url

  task_cpu      = var.agent_task_cpu
  task_memory   = var.agent_task_memory
  desired_count = var.agent_desired_count

  # Sin valor todavia: en prod solo esta desplegado el contexto `identity`
  # del backend, asi que no existe una API de informes a la que registrar.
  # Cuando se despliegue, su URL va aqui igual que en dev. Mientras tanto el
  # agente funciona y solo la emision de informes avisa de que falta.
  backend_api_url = var.reports_api_url

  # Solo el dominio CloudFront de prod (sin localhost, a diferencia de dev).
  cors_allowed_origins = jsonencode([
    "https://${module.frontend_hosting.frontend_distribution_domain_name}",
  ])

  log_retention_days = var.agent_log_retention_days
  kms_key_arn        = module.kms.kms_key_arn

  # Va en pareja con kms_key_arn. El modulo no puede deducirlo del ARN porque
  # es un atributo computado y `count` no admite valores desconocidos en plan.
  # Es justo lo que rompio el primer plan-prod que llego a ejecutarse.
  enable_kms_encryption = true

  # true en prod: protege el ALB (y con el, el DNS publicado en SSM) contra
  # un destroy accidental.
  enable_deletion_protection = var.agent_enable_deletion_protection
}
