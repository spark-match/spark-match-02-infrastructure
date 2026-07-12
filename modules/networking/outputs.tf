###############################################################################
# Outputs de modules/networking
###############################################################################

output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN de la VPC."
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "CIDR principal de la VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las subnets publicas (una por AZ)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas (una por AZ)."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID de la route table publica."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs de las route tables privadas (1 sola si enable_nat_ha=false; 1 por AZ si true)."
  value       = aws_route_table.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs de los NAT Gateways. Empty list si enable_nat_gateway=false."
  value       = aws_nat_gateway.main[*].id
}

output "internet_gateway_id" {
  description = "ID del Internet Gateway."
  value       = aws_internet_gateway.main.id
}
