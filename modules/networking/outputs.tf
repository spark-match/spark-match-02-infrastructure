output "vpc_id" {
  description = "ID de la VPC creada."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "Bloque CIDR principal de la VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Lista de IDs de las subnets publicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Lista de IDs de las subnets privadas."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway (si fue creado)."
  value       = var.enable_nat_gateway ? aws_nat_gateway.main[0].id : null
}

output "internet_gateway_id" {
  description = "ID del Internet Gateway."
  value       = aws_internet_gateway.main.id
}