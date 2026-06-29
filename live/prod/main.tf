###############################################################################
# Spark Match - Infraestructura productiva
###############################################################################
#
# Fase 1 (actual):
#   - module "s3_example"   -> POC de Terraform + AWS (bucket de ejemplo)
#
# Fase 1 (desactivada, modulo listo pero sin aplicar):
#   - module "networking"   -> VPC + subnets + IGW
#
# Fases futuras (a desarrollar):
#   - module "database"     -> RDS PostgreSQL (Fase 2)
#   - module "storage"      -> S3 buckets definitivos (Fase 2)
#   - module "compute"      -> ECS Fargate (Fase 3)
#   - module "cdn"          -> CloudFront (Fase 3)
#   - module "security"     -> IAM roles, security groups (Fase 4)
#   - module "secrets"      -> Secrets Manager (Fase 4)
#   - module "monitoring"   -> CloudWatch + SNS (Fase 4)
#   - module "bedrock"      -> IAM para AWS Bedrock (Fase 4)
#

###############################################################################
# POC: Bucket S3 de ejemplo
###############################################################################

module "s3_example" {
  source = "../../modules/s3-example"

  # El sufijo aleatorio asegura unicidad global del nombre.
  bucket_name        = "${var.project_name}-poc-ejemplo-${var.bucket_suffix}"
  versioning_enabled = true

  tags = local.common_tags
}

###############################################################################
# Networking (NO SE APLICA AUN)
###############################################################################
# Descomentar cuando estemos listos para desplegar la VPC.
#
# module "networking" {
#   source = "../../modules/networking"
#
#   vpc_name             = "${var.project_name}-${var.environment}"
#   vpc_cidr             = var.vpc_cidr
#   azs                  = var.azs
#   public_subnet_cidrs  = var.public_subnet_cidrs
#   private_subnet_cidrs = var.private_subnet_cidrs
#   enable_nat_gateway   = false
#
#   tags = local.common_tags
# }