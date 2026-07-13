###############################################################################
# Module: notifications
#
# Cubre los recursos "de cuenta" relacionados a notificaciones operacionales
# de Spark Match, independientes del environment:
#   - SNS topic para alertas de AWS Budget
#   - SNS topic policy (permite publish a budgets.amazonaws.com)
#   - SNS topic subscriptions (email)
#   - AWS Budget (spark-match-monthly-total, $200/mes, COST)
#
# Por que este modulo es de cuenta (no de environment):
#   - AWS Budget es un recurso de cuenta, no se replica por env.
#   - SNS topic es compartido (mismo ARN para todos los envs).
#   - Las suscripciones de email son del equipo (independiente del env).
#   - Si en el futuro hay alerting diferenciado por env, se puede partir en
#     modules/notifications (cuenta) + modules/dev/notifications, etc.
#
# Decisiones de diseno:
#   - SNS topic sin KMS (default encryption del lado del server). Las alertas
#     no contienen datos sensibles, solo notificaciones de presupuesto.
#   - Display name vacio (default) para no exponer el topic en busquedas del
#     console de SNS.
#   - EffectiveDeliveryPolicy default (20s, 3 retries, linear backoff).
#   - Suscripciones via for_each sobre `var.email_endpoints`. Agregar/quitar
#     correos = editar el .tf y aplicar.
#   - AWS Budget incluye 2 notifications embebidas:
#     * ACTUAL > 80% (alerta cuando el costo real acumulado del mes llega al 80%)
#     * FORECASTED > 100% (alerta cuando AWS pronostica que el mes cerrara > $200)
#   - Limit PERCENTAGE para que el threshold funcione independiente del BudgetLimit
#     (si subimos el limite a $400, el threshold sigue siendo 80% y 100% del nuevo).
###############################################################################

###############################################################################
# Locals: common tags
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "notifications"
      Project     = var.project_name
      Environment = "shared"
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )
}

###############################################################################
# SNS topic
###############################################################################

resource "aws_sns_topic" "budget_alerts" {
  name = var.topic_name

  # KMS master key NO seteado: default encryption (AES256 managed by AWS).
  # Las alertas de budget no contienen datos sensibles.
  # Si en el futuro se envia info sensible (ej. PII), cambiar a KMS CMK.

  tags = merge(local.common_tags, {
    Name = var.topic_name
  })
}

###############################################################################
# SNS topic policy
#
# Solo permite publish desde `budgets.amazonaws.com`. Sin esta policy, AWS
# Budgets no podria mandar mensajes al topic. Nadie mas puede publicar.
###############################################################################

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "budget_alerts" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "SparkMatchBudgetAlertsPolicy"
    Statement = [
      {
        Sid    = "AllowBudgetsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.budget_alerts.arn
      },
    ]
  })
}

###############################################################################
# SNS topic subscriptions (email)
#
# for_each sobre el set de emails. Las suscripciones quedan en estado
# "PendingConfirmation" hasta que cada destinatario confirme el link que
# AWS le envia por email. Limitacion de AWS SNS, no se puede auto-confirmar.
#
# IMPORTANTE: si se quita un email de la lista, Terraform elimina la suscripcion
# (no hay confirmacion pendiente, se borra directo).
###############################################################################

resource "aws_sns_topic_subscription" "email" {
  for_each = var.email_subscriptions

  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

###############################################################################
# AWS Budget (cost budget mensual)
#
# Budget name: spark-match-monthly-total
# Limit: $200 USD/mes
# Type: COST (basado en costo real, no en uso planificado)
# TimeUnit: MONTHLY (reset el primer dia de cada mes)
#
# CostTypes: defaults (todos los cargos incluidos: tax, refunds, credits,
# recurring, support, discount, etc). UseBlended=false porque queremos ver
# costos on-demand reales, no promediados.
#
# 2 notifications embebidas (estan dentro del recurso aws_budgets_budget):
#   1. ACTUAL > 80% (alerta reactiva: ya gastamos $160 este mes)
#   2. FORECASTED > 100% (alerta predictiva: AWS pronostica que cerraremos > $200)
#
# Ambas envian al mismo SNS topic que las suscripciones de email.
###############################################################################

resource "aws_budgets_budget" "monthly" {
  name         = var.budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_tax             = true
    include_subscription    = true
    use_blended             = false
    include_refund          = true
    include_credit          = true
    include_upfront         = true
    include_recurring       = true
    include_other_subscription = true
    include_support         = true
    include_discount        = true
  }

  # Notification 1: ACTUAL > 80%
  # Cuando el costo real acumulado del mes llega al 80% de $200 (=$160).
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [] # vacio porque usamos SNS
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Notification 2: FORECASTED > 100%
  # Cuando AWS pronostica que el costo del mes cerrara arriba de $200.
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_email_addresses = [] # vacio porque usamos SNS
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  tags = local.common_tags
}