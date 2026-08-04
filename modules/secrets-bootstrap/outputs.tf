output "jwt_secret_arn" {
  description = "ARN del secret JWT. Consumido por el SSM parameter /spark-match/{env}/config/jwt-secret-arn."
  value       = aws_secretsmanager_secret.jwt_secret.arn
}

output "jwt_secret_name" {
  description = "Nombre del secret JWT (spark-match-{env}-jwt-secret)."
  value       = aws_secretsmanager_secret.jwt_secret.name
}
