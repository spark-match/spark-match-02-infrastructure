output "vpc_id" {
  description = "ID de la VPC productiva."
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR principal de la VPC."
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las subnets publicas (para ALB, CloudFront, etc.)."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (para ECS Fargate, RDS, etc.)."
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway."
  value       = module.networking.nat_gateway_id
}