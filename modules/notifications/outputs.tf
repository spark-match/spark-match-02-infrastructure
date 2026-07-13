###############################################################################
# Outputs de modules/notifications
###############################################################################

output "topic_arn" {
  description = "ARN del SNS topic para alertas de budget."
  value       = aws_sns_topic.budget_alerts.arn
}

output "topic_name" {
  description = "Nombre del SNS topic."
  value       = aws_sns_topic.budget_alerts.name
}

output "subscription_endpoints" {
  description = "Lista de emails subscriptos al topic."
  value       = [for sub in aws_sns_topic_subscription.email : sub.endpoint]
}

output "subscription_keys" {
  description = "Lista de keys (nombres logicos) de suscriptores."
  # El key de for_each no es un atributo del recurso; se accede via
  # `aws_sns_topic_subscription.email` (el map).
  value = keys(aws_sns_topic_subscription.email)
}

output "subscription_map" {
  description = "Mapa key -> email de todos los suscriptores."
  value       = aws_sns_topic_subscription.email
}

output "budget_name" {
  description = "Nombre del AWS Budget."
  value       = aws_budgets_budget.monthly.name
}

output "budget_limit_amount" {
  description = "Limite mensual del budget en USD."
  value       = aws_budgets_budget.monthly.limit_amount
}

output "kms_key_arn" {
  description = "ARN de la CMK de KMS que cifra el SNS topic."
  value       = aws_kms_key.sns.arn
}

output "kms_key_alias" {
  description = "Alias legible de la CMK."
  value       = aws_kms_alias.sns.name
}