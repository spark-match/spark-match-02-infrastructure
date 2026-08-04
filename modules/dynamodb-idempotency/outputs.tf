output "table_name" {
  description = "Nombre de la tabla DynamoDB de idempotencia (spark-match-{env}-idempotency)."
  value       = aws_dynamodb_table.idempotency.name
}

output "table_arn" {
  description = "ARN de la tabla DynamoDB de idempotencia."
  value       = aws_dynamodb_table.idempotency.arn
}
