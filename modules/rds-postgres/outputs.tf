output "db_instance_id" {
  description = "Identifier de la instancia RDS."
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "ARN de la instancia RDS."
  value       = aws_db_instance.main.arn
}

output "db_address" {
  description = "Endpoint (hostname) de la instancia RDS, sin el puerto."
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "Puerto de la instancia RDS (5432)."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Nombre de la base de datos inicial."
  value       = aws_db_instance.main.db_name
}

output "db_credentials_secret_arn" {
  description = "ARN del secret con credenciales completas (host/port/database/username/password). Consumido por el SSM parameter /spark-match/{env}/config/db-secret-arn."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_credentials_secret_name" {
  description = "Nombre del secret de credenciales (spark-match-{env}-db-credentials)."
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "connection_url" {
  description = "Postgres connection URL completa (postgres://user:pass@host:port/db). SENSITIVE -- consumido solo por el SSM SecureString /spark-match/{env}/config/db-connection-url (Lambda migrate)."
  value       = local.connection_url
  sensitive   = true
}
