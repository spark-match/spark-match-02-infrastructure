###############################################################################
# Outputs de modules/security
#
# Convencion: los outputs apuntan al ARN (para IAM) o al ID/KeyId (para KMS/SG).
# NOTA: los outputs de los 4 IAM roles (sam_deploy, bedrock_deploy, lambda_runtime,
# agentcore_runtime) fueron extraidos a modules/oidc-github en PR4a (Sprint 1).
# Los consumers deben usar `module.oidc_github.*_role_arn` en lugar de
# `module.security.*_role_arn`.
###############################################################################

# -- KMS --
output "kms_key_arn" {
  description = "ARN de la CMK de Spark Match para este entorno."
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "KeyId de la CMK (util para policies que esperan key id, no arn)."
  value       = aws_kms_key.main.key_id
}

output "kms_alias_arn" {
  description = "ARN del alias CMK."
  value       = aws_kms_alias.main.arn
}

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
