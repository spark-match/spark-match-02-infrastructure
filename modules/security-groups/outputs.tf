output "sg_lambda_id" {
  description = "ID del SG para Lambdas."
  value       = aws_security_group.lambda.id
}

output "sg_lambda_arn" {
  description = "ARN del SG para Lambdas."
  value       = aws_security_group.lambda.arn
}

output "sg_rds_id" {
  description = "ID del SG para RDS/Aurora."
  value       = aws_security_group.rds.id
}

output "sg_rds_arn" {
  description = "ARN del SG para RDS/Aurora."
  value       = aws_security_group.rds.arn
}

output "sg_endpoints_id" {
  description = "ID del SG para VPC endpoints."
  value       = aws_security_group.endpoints.id
}

output "sg_endpoints_arn" {
  description = "ARN del SG para VPC endpoints."
  value       = aws_security_group.endpoints.arn
}
