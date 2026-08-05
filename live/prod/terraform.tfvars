###############################################################################
# terraform.tfvars para live/prod
###############################################################################
# Este archivo define los valores reales del entorno productivo y se commitea
# al repo. NO debe contener secretos. Para secretos usar SSM Parameter Store
# o Secrets Manager (modulos secrets/ en Fase 2).
#
# Si queres hacer overrides locales sin commitear, crea terraform.tfvars.local
# (gitignored) o pasa -var-file=/ruta/al/archivo.tfvars.
###############################################################################

aws_region   = "us-east-1"
project_name = "spark-match"
environment  = "prod"

###############################################################################
# Networking (modulo networking - se usara en Fase 1.5)
###############################################################################

# CIDR base de prod. Separado de dev (10.10.0.0/16) para evitar colisiones si
# en algun momento se hace VPC peering o Transit Gateway entre envs.
vpc_cidr             = "10.0.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# Prod (checkpoint de costos 2026-08-04): NAT unico en vez de HA. Con
# enable_nat_ha=true, la caida de una AZ no deja a las Lambdas sin salida a
# internet, pero cuesta 2 NAT Gateway + 2 EIP (~$73/mes). NAT unico ahorra
# ~$36.50/mes (1 NAT + 1 EIP) a cambio de un unico punto de fallo por NAT;
# revisar si el trafico real de prod justifica volver a HA.
enable_nat_gateway = true
enable_nat_ha      = false

###############################################################################
# Endpoints (modulo endpoints - se usara en Fase 1.5)
###############################################################################

# Prod (checkpoint de costos 2026-08-04): solo los interface endpoints
# realmente usados, en 1 AZ (ver interface_endpoint_subnet_ids en main.tf).
# Con NAT presente, el resto del trafico AWS sale por NAT sin problema.
# Antes: 11 endpoints x 2 AZ = 22 ENI (~$160.60/mes). Ahora: 4 endpoints x 1
# AZ = 4 ENI (~$29.20/mes). Ahorro: ~$131.40/mes.
enable_all_endpoints_by_default = false
enabled_endpoints               = ["secretsmanager", "events", "ssm", "bedrock-runtime"]
enable_s3_gateway_endpoint      = true

# Flow logs: activado en prod para auditoria y debugging. Costo estimado
# ~$5-10/mes segun volumen de trafico. Retencion 365 dias (1 anio, minimo
# exigido por CKV_AWS_338 ademas de buena practica de auditoria).
enable_flow_logs        = true
flow_log_traffic_type   = "REJECT"
flow_log_retention_days = 365

###############################################################################
# Security (modulo security - se usara en Fase 1.5)
###############################################################################

# CMK deletion window: 30 dias para prod (maximo AWS, estandar para CMK
# productiva). Da tiempo de rollback ante un destroy accidental.
kms_deletion_window_in_days = 30

# Repos permitidos a asumir los roles OIDC prod.
sam_deploy_github_repos = [
  "spark-match/spark-match-03-backend",
]

bedrock_deploy_github_repos = [
  "spark-match/spark-match-08-deep-agent",
]

###############################################################################
# Fase 2 (modulos storage, secrets, events, dynamodb, rds, ssm — ADR 0002)
###############################################################################

# false en prod (a diferencia de dev): evita que terraform destroy borre el
# bucket de artefactos SAM aunque tenga objetos vigentes.
sam_artifacts_force_destroy = false

# 30 en prod (maximo, a diferencia de dev que usa 0): protege los secrets
# (JWT, credenciales RDS) contra borrado accidental/definitivo.
secrets_recovery_window_in_days = 30

# TODO: reemplazar por el dominio real de spark-match-04-frontend antes del
# primer apply real a prod. El frontend aun no existe/despliega, por lo que
# este es un placeholder deliberadamente invalido (no debe resolver a un
# origen real hasta que se actualice).
cors_allowed_origins = "https://TODO-set-real-frontend-domain.spark-match.example"

# 0 en prod: la cuenta AWS 681526276858 tiene guardrails de "Free Tier
# account" (distinto del free-tier clasico) que rechazan CreateDBInstance con
# FreeTierRestrictionError si backup_retention_period > 0. Prod usa LA MISMA
# cuenta AWS que dev (ver AGENTS.md tabla Multi-env), por lo que el mismo
# guardrail aplica. Riesgo operacional conocido y aceptado por ahora: sin
# backups automaticos de RDS en prod. Revisar antes del primer apply real
# (upgrade de cuenta AWS, o cuenta separada para prod).
rds_backup_retention_period_days = 0

# db.t4g.small (2GiB RAM): punto de partida conservador, mas grande que dev
# (db.t4g.micro, 1GiB) sin sobre-aprovisionar antes de tener datos reales de
# carga. Ajustar segun metricas post-launch.
db_instance_class = "db.t4g.small"

###############################################################################
# Frontend hosting (modules/frontend-hosting + modules/oidc-frontend)
###############################################################################

# false en prod: protege los assets de deploy vigentes contra borrado accidental.
frontend_force_destroy = false

# 90 en prod: retencion extendida para auditoria de cambios en el frontend.
frontend_access_logs_retention_days         = 90
frontend_noncurrent_version_expiration_days = 90
