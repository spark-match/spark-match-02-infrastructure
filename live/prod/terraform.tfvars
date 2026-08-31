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
  # Fase 2 del rename, completada 2026-08-31: el repo ya se llama
  # spark-match-07-deep-agent y el nombre viejo sale del trust policy.
  # El claim `sub` de GitHub Actions lleva el nombre actual del repo y AWS
  # lo compara literal, asi que esta lista tiene que seguir al repo.
  "spark-match/spark-match-07-deep-agent",
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

# cors_allowed_origins ya no se declara aqui. El valor es el dominio de la
# distribucion CloudFront, que no se conoce hasta que este mismo fichero se
# aplique, asi que ninguna constante podia ser correcta. Ahora se deriva del
# output del modulo en main.tf. Ver la nota junto a module "ssm_bootstrap".

# 0 en prod: la cuenta AWS 681526276858 tiene guardrails de "Free Tier
# account" (distinto del free-tier clasico) que rechazan CreateDBInstance con
# FreeTierRestrictionError si backup_retention_period > 0. Prod usa LA MISMA
# cuenta AWS que dev (ver AGENTS.md tabla Multi-env), por lo que el mismo
# guardrail aplica.
#
# DECISION TOMADA, no pendiente. Este comentario decia "revisar antes del
# primer apply real (upgrade de cuenta AWS, o cuenta separada para prod)".
# Se reviso el 2026-08-07 y la respuesta es que se queda en 0: spark-match es
# un proyecto de curso y el objetivo es ejercitar las tecnologias, no sostener
# un servicio con compromiso de recuperacion. Se descartaron explicitamente
# sacar la cuenta del plan Free Tier y montar snapshots manuales -- estos
# ultimos SI serian posibles, porque el guardrail solo rechaza la retencion
# automatica, pero no se consideran necesarios.
#
# Consecuencia, dicha sin adornos: prod no tiene backups de base de datos. Si
# se pierde la instancia, se pierden los datos. Si algun dia esto deja de ser
# un proyecto de curso, esta es la primera linea que hay que cambiar, y exige
# antes sacar la cuenta del Free Tier o mover prod a una cuenta propia.
rds_backup_retention_period_days = 0

# db.t4g.micro, igual que dev. Decia db.t4g.small "como punto de partida
# conservador", y el primer apply real de prod lo tumbo el 2026-08-07:
#
#   FreeTierRestrictionError: This instance size isn't available with free
#   plan accounts. To remove all limitations, upgrade your account plan.
#
# Es el MISMO guardrail que ya obligo a poner la retencion de backups a 0
# treinta lineas mas arriba. Aquel se razono y este se paso por alto, porque
# el guardrail no aparece en el plan: `terraform plan` da los 125 recursos por
# buenos y el rechazo solo llega al crear la instancia de verdad.
#
# Se mantiene la decision ya tomada de no sacar la cuenta del plan Free Tier:
# spark-match es un proyecto de curso y el objetivo es ejercitar las
# tecnologias. Asi que la talla baja a la que el plan si admite, que es la
# misma que lleva dev funcionando.
#
# Consecuencia: prod y dev tienen la misma capacidad de base de datos (1GiB).
# Si algun dia esto deja de ser un proyecto de curso, esta linea y la de
# `rds_backup_retention_period_days` se cambian juntas, y las dos exigen antes
# sacar la cuenta del Free Tier o mover prod a una cuenta propia.
db_instance_class = "db.t4g.micro"

###############################################################################
# Frontend hosting (modules/frontend-hosting + modules/oidc-frontend)
###############################################################################

# false en prod: protege los assets de deploy vigentes contra borrado accidental.
frontend_force_destroy = false

# 90 en prod: retencion extendida para auditoria de cambios en el frontend.
frontend_access_logs_retention_days         = 90
frontend_noncurrent_version_expiration_days = 90

###############################################################################
# Deep agent (modules/ecr + modules/agent-service)
###############################################################################

# Interruptor de costo del agente: Fargate 0.5 vCPU / 1 GiB (~$18/mes) + ALB
# (~$17.50/mes) + ECR (~$0.30/mes) = ~$36/mes. Con los ~$101/mes del resto de
# prod (tras los recortes del checkpoint 2026-08-04) el total queda en
# ~$137/mes, bajo el budget de $200/mes de la cuenta.
enable_agent_service = true

# 1 task: el estado de conversacion vive en Postgres (schema `agent`), no en
# memoria de la task, asi que escalar horizontalmente es solo subir este
# numero cuando el trafico lo justifique.
agent_desired_count = 1
agent_task_cpu      = 512
agent_task_memory   = 1024

# Protecciones de prod (a diferencia de dev): el repositorio ECR no se borra
# con imagenes dentro y el ALB tiene deletion protection -- su DNS queda
# publicado en SSM y consumido por el frontend.
agent_ecr_force_delete           = false
agent_enable_deletion_protection = true

# 365 dias: mismo minimo de 1 anio que exige CKV_AWS_338 para el resto de los
# log groups productivos.
agent_log_retention_days = 365
