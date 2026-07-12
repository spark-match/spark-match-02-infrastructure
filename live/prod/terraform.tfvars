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

# Prod: NAT HA (1 NAT por AZ) para que la caida de una AZ no deje a las
# Lambdas sin salida a internet. Costo extra: ~$64/mes (2 NAT Gateway + 2 EIP).
enable_nat_gateway = true
enable_nat_ha      = true

###############################################################################
# Endpoints (modulo endpoints - se usara en Fase 1.5)
###############################################################################

# Prod: TODOS los interface endpoints + S3 gateway para mantener trafico AWS
# privado (sin atravesar NAT ni internet). Costo: ~$72/mes (10 interface
# endpoints x $0.01/h).
enable_all_endpoints_by_default = true
enable_s3_gateway_endpoint      = true

# Flow logs: activado en prod para auditoria y debugging. Costo estimado
# ~$5-10/mes segun volumen de trafico. Retencion 90 dias.
enable_flow_logs          = true
flow_log_traffic_type     = "REJECT"
flow_log_retention_days   = 90

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
