output "repository_name" {
  description = "Nombre del repositorio ECR (ej. spark-match-agent-advisor-dev). El workflow de deploy de spark-match-08-deep-agent lo necesita como `vars.ECR_REPOSITORY_{DEV,PROD}`."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "ARN del repositorio ECR."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "URL del repositorio ECR (`{account}.dkr.ecr.{region}.amazonaws.com/{name}`), usada como base del tag de imagen en el push y en la task definition de ECS."
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "Account ID del registry ECR."
  value       = aws_ecr_repository.this.registry_id
}
