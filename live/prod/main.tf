###############################################################################
# Spark Match - Infraestructura productiva (Fase 1: networking)
###############################################################################

module "networking" {
  source = "../../modules/networking"

  vpc_name             = "${var.project_name}-${var.environment}"
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = false

  tags = local.common_tags
}

# Aqui iran el resto de modulos en fases posteriores:
#   module "database"   { source = "../../modules/database"   ... }
#   module "storage"    { source = "../../modules/storage"    ... }
#   module "compute"    { source = "../../modules/compute"    ... }
#   module "cdn"        { source = "../../modules/cdn"        ... }
#   module "security"   { source = "../../modules/security"   ... }
#   module "secrets"    { source = "../../modules/secrets"    ... }
#   module "monitoring" { source = "../../modules/monitoring" ... }
#   module "bedrock"    { source = "../../modules/bedrock"    ... }