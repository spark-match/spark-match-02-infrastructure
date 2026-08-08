###############################################################################
# terraform.tfvars para live/dev
###############################################################################
# Este archivo define los valores reales del entorno dev y se commitea al repo.
# NO debe contener secretos. Para secretos usar SSM Parameter Store o
# Secrets Manager (modulos secrets/ en Fase 2).
#
# Si queres hacer overrides locales sin commitear, crea terraform.tfvars.local
# (gitignored) o pasa -var-file=/ruta/al/archivo.tfvars.
###############################################################################

aws_region   = "us-east-1"
project_name = "spark-match"
environment  = "dev"

###############################################################################
# Networking (modulo networking - se usara en Fase 1.5)
###############################################################################

# CIDR separado de prod para evitar colisiones si en algun momento se hace
# VPC peering o Transit Gateway entre envs.
vpc_cidr             = "10.10.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]

# Dev no necesita salida a internet: las Lambdas solo hablan con VPC endpoints
# y servicios internos. Costo: $0 en NAT.
enable_nat_gateway = false
enable_nat_ha      = false

###############################################################################
# Endpoints (modulo endpoints)
###############################################################################

# Decision de arquitectura dev (ADR 0002 §4 — VPC + 2 interface endpoints, sin NAT):
#   Las Lambdas de 03-backend corren DENTRO de la VPC (subnet privada) porque
#   RDS Postgres estandar (NO Aurora, ver PR #131) no tiene Data API HTTPS --
#   la unica forma de conectar es via TCP 5432, que requiere estar en la VPC
#   o exponer RDS publicamente (descartado por seguridad).
#   Sin NAT, las unicas llamadas SDK salientes que necesitan salida son:
#     - Secrets Manager (leer credenciales frescas de RDS en cada invocacion)
#     - EventBridge (PutEvents para eventos de dominio)
#     - SSM Parameter Store (03-backend resuelve en runtime los parametros
#       del contrato ADR-0002 /spark-match/{env}/config/*: bus-arn en
#       composition.ts, jwt-arn en jwt-secret-loader.ts y db-connection-url
#       en la lambda migrate)
#   Se resuelven con interface endpoints en 1 sola AZ (no las 2) para
#   reducir costo: cada ENI adicional por AZ cuesta ~$7.20/mes por endpoint.
#   CloudWatch Logs y X-Ray no requieren NAT ni VPC endpoint (viajan por el
#   plano de control de Lambda, no por la ENI de la funcion).
#   Costo networking dev: ~$21.90/mes (3 endpoints x 1 AZ), sin NAT.
enable_all_endpoints_by_default = false
enabled_endpoints               = ["secretsmanager", "events", "ssm"]
enable_s3_gateway_endpoint      = true

# Flow logs: desactivado en dev para minimizar costo (~$0.50/mes si esta
# prendido y hay trafico). Se puede activar localmente con -var si se necesita
# debuggear trafico de red en una sesion.
enable_flow_logs = false

###############################################################################
# Security (modulo security - se usara en Fase 1.5)
###############################################################################

# CMK deletion window: 7 dias para dev (mas rapido si hay que borrar el key).
kms_deletion_window_in_days = 7

# Repos permitidos a asumir los roles OIDC dev. Esto matchea el sub claim
# del token OIDC emitido por GitHub Actions.
sam_deploy_github_repos = [
  "spark-match/spark-match-03-backend",
]

bedrock_deploy_github_repos = [
  "spark-match/spark-match-08-deep-agent",
]

###############################################################################
# Fase 2 (modulos storage, secrets, events, dynamodb, rds, ssm — ADR 0002)
###############################################################################

# true en dev: permite terraform destroy sin vaciar el bucket de artefactos SAM a mano.
sam_artifacts_force_destroy = true

# 0 en dev: permite recrear secrets (JWT, credenciales RDS) sin esperar el
# recovery window de Secrets Manager mientras iteramos.
secrets_recovery_window_in_days = 0

# '*' en dev: el frontend local (Vite, distintos puertos) necesita CORS abierto.
# En prod esto debe ser una lista explicita de dominios.
cors_allowed_origins = "*"

# 0 en dev: la cuenta AWS 681526276858 tiene guardrails de "Free Tier account"
# (distinto del free-tier clasico) que rechazan CreateDBInstance con
# FreeTierRestrictionError si backup_retention_period > 0. Confirmado en el
# primer apply real (2026-08-04): un valor de 7 dias fue rechazado por la API
# de RDS. Prod debe usar >= 7 en su propio terraform.tfvars.
rds_backup_retention_period_days = 0

###############################################################################
# Frontend hosting (modules/frontend-hosting + modules/oidc-frontend)
###############################################################################

# true en dev: permite `terraform destroy` sin vaciar el bucket frontend a mano
# mientras iteramos en la build estatico de 04-frontend.
frontend_force_destroy = true

# 30 en dev: rotacion rapida de los CloudFront access logs.
frontend_access_logs_retention_days         = 30
frontend_noncurrent_version_expiration_days = 30

###############################################################################
# Deep agent (modules/agent-service)
###############################################################################

# El VALOR de la key NO esta aqui ni en el tfstate: este es solo el nombre del
# secret, y Terraform resuelve su ARN con un data source. El secret hay que
# crearlo antes de aplicar esto o el plan falla. Procedimiento completo en
# docs/runbook-tavily.md.
#
# Mientras estuvo en null, `web_search` caia siempre a DuckDuckGo. Medido en
# los logs de dev el 2026-08-08, esa caida no es benigna:
#
#   Tavily search failed (ValueError), falling back to DuckDuckGo:
#     TAVILY_API_KEY not configured
#   Web search completed via DuckDuckGo (fallback): 0 results
#
# Cero resultados, no peores resultados. O sea que cualquier pregunta que
# dependa de informacion actual (fechas de Beca 18, admisiones) no se podia
# responder.
agent_tavily_secret_name = "spark-match-dev-tavily-api-key"
