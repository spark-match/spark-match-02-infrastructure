output "interface_endpoint_ids" {
  description = "Map de IDs de los interface endpoints por nombre corto (ssm, ecr.api, etc.)."
  value       = { for k, ep in aws_vpc_endpoint.interface : k => ep.id }
}

output "interface_endpoint_dns_entries" {
  description = "DNS entries de los interface endpoints (map nombre_corto -> lista de IPs privadas, una por subnet)."
  value       = { for k, ep in aws_vpc_endpoint.interface : k => ep.dns_entry[*].dns_name }
}

output "s3_gateway_endpoint_id" {
  description = "ID del gateway endpoint para S3. Null si enable_s3_gateway_endpoint=false."
  value       = var.enable_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].id : null
}
