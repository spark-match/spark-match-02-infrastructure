###############################################################################
# Outputs de modules/security
#
# PR4a (Sprint 1): los 4 IAM role outputs fueron extraidos a modules/oidc-github.
# PR4b (Sprint 1): los 3 KMS CMK outputs fueron extraidos a modules/kms.
# Este modulo ahora solo expone los 3 Security Groups + sus IDs.
#
# Convencion: los outputs apuntan al ARN (para IAM) o al ID/KeyId (para KMS/SG).
###############################################################################

# -- Security groups --
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
