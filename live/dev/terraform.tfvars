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
# Endpoints (modulo endpoints - se usara en Fase 1.5)
###############################################################################

# Dev: solo el S3 gateway endpoint (gratis). El resto del trafico AWS se hace
# desde la Lambda ENI hacia los service endpoints publicos (sin NAT, gracias
# a que el SDK de boto3 resuelve hacia el endpoint regional publico sin
# necesidad de NAT cuando la Lambda tiene internet access via egress SG).
# En la practica, esto significa que el agente (08-deep-agent) puede llamar
# a Bedrock sin NAT porque la Lambda tiene egress 0.0.0.0/0 en el SG lambda.
enable_all_endpoints_by_default = false
enable_s3_gateway_endpoint      = true

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
