output "deploy_role_arn" {
  description = "ARN del role OIDC asumido por spark-match-04-frontend para deploy (S3 + CloudFront invalidation)."
  value       = aws_iam_role.frontend_deploy.arn
}

output "deploy_role_name" {
  description = "Nombre del role OIDC (spark-match-frontend-deploy-{env})."
  value       = aws_iam_role.frontend_deploy.name
}
