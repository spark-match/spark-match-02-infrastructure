output "bus_name" {
  description = "Nombre del bus de EventBridge (spark-match-events-{env})."
  value       = aws_cloudwatch_event_bus.main.name
}

output "bus_arn" {
  description = "ARN del bus de EventBridge. Consumido por el SSM parameter /spark-match/{env}/config/eventbridge-bus-arn y por la IAM policy EventBridgePutEventsPolicy del backend."
  value       = aws_cloudwatch_event_bus.main.arn
}

output "archive_arn" {
  description = "ARN del archive de eventos."
  value       = aws_cloudwatch_event_archive.main.arn
}

output "dlq_arn" {
  description = "ARN de la DLQ para target failures de reglas de EventBridge."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL de la DLQ."
  value       = aws_sqs_queue.dlq.id
}
