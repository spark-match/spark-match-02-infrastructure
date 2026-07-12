###############################################################################
# Outputs de modules/security
#
# Convencion: los outputs apuntan al ARN (para IAM) o al ID/KeyId (para KMS/SG).
# Los consumers (live/prod, otros modulos downstream) deben importarlos con
# `data "aws_ssm_parameter"` cruzando la frontera a repos externos.
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

# -- IAM OIDC roles --
output "sam_deploy_role_arn" {
  description = "ARN del role OIDC spark-match-sam-deploy. Wire a GitHub secret AWS_SAM_DEPLOY_ROLE_ARN en spark-match-03-backend."
  value       = aws_iam_role.sam_deploy.arn
}

output "sam_deploy_role_name" {
  description = "Nombre del role OIDC spark-match-sam-deploy."
  value       = aws_iam_role.sam_deploy.name
}

output "bedrock_deploy_role_arn" {
  description = "ARN del role OIDC spark-match-bedrock-agentcore-deploy. Wire a GitHub secret AWS_BEDROCK_AGENTCORE_DEPLOY_ROLE_ARN en spark-match-08-deep-agent."
  value       = aws_iam_role.bedrock_deploy.arn
}

output "bedrock_deploy_role_name" {
  description = "Nombre del role OIDC spark-match-bedrock-agentcore-deploy."
  value       = aws_iam_role.bedrock_deploy.name
}

# -- IAM execution roles --
output "lambda_runtime_role_arn" {
  description = "ARN del execution role para Lambdas. Referenciar desde 03-backend/template.yaml."
  value       = aws_iam_role.lambda_runtime.arn
}

output "lambda_runtime_role_name" {
  description = "Nombre del execution role para Lambdas."
  value       = aws_iam_role.lambda_runtime.name
}

output "agentcore_runtime_role_arn" {
  description = "ARN del execution role para el contenedor FastAPI en AgentCore."
  value       = aws_iam_role.agentcore_runtime.arn
}

output "agentcore_runtime_role_name" {
  description = "Nombre del execution role para AgentCore."
  value       = aws_iam_role.agentcore_runtime.name
}
