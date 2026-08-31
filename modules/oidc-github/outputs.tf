###############################################################################
# Outputs de modules/oidc-github
###############################################################################

# -- OIDC provider --
output "oidc_provider_arn" {
  description = "ARN del OIDC provider para GitHub Actions. SINGLETON a nivel de cuenta AWS."
  value       = local.oidc_provider_arn
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
  description = "ARN del role OIDC spark-match-bedrock-agentcore-deploy. Wire a GitHub secret AWS_BEDROCK_AGENTCORE_DEPLOY_ROLE_ARN en spark-match-07-deep-agent."
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
