###############################################################################
# Outputs del entorno prod
###############################################################################

# --- POC: S3 bucket de ejemplo ---
output "s3_example_bucket_id" {
  description = "Nombre del bucket S3 de POC."
  value       = module.s3_example.bucket_id
}

output "s3_example_bucket_arn" {
  description = "ARN del bucket S3 de POC."
  value       = module.s3_example.bucket_arn
}

output "s3_example_bucket_region" {
  description = "Region AWS donde se creo el bucket S3 de POC."
  value       = module.s3_example.bucket_region
}

output "s3_example_bucket_domain_name" {
  description = "Domain name del bucket S3 de POC."
  value       = module.s3_example.bucket_domain_name
}

output "s3_example_versioning_enabled" {
  description = "Estado del versionado del bucket S3 de POC."
  value       = module.s3_example.versioning_enabled
}

# --- Networking (desactivado, descomentar cuando se aplique) ---
# output "vpc_id" {
#   description = "ID de la VPC productiva."
#   value       = module.networking.vpc_id
# }
#
# output "vpc_cidr_block" {
#   description = "CIDR principal de la VPC."
#   value       = module.networking.vpc_cidr_block
# }
#
# output "public_subnet_ids" {
#   description = "IDs de las subnets publicas (para ALB, CloudFront, etc.)."
#   value       = module.networking.public_subnet_ids
# }
#
# output "private_subnet_ids" {
#   description = "IDs de las subnets privadas (para ECS Fargate, RDS, etc.)."
#   value       = module.networking.private_subnet_ids
# }
#
# output "nat_gateway_id" {
#   description = "ID del NAT Gateway."
#   value       = module.networking.nat_gateway_id
# }