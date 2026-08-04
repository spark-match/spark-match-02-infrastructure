###############################################################################
# Module: eventbridge-bus
#
# Bus de EventBridge custom para los eventos de dominio de Spark Match
# (UserRegistered, UserLoggedIn, UserUpdated, etc. — ver
# 03-backend/contexts/identity/src/service/user-service.ts). Incluye archive
# para replay/debug y una DLQ para cuando existan reglas con target Lambda/SQS
# que fallen su entrega.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "eventbridge-bus"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  bus_name = "${var.project_name}-events-${var.environment}"
}

resource "aws_cloudwatch_event_bus" "main" {
  name = local.bus_name

  tags = merge(local.common_tags, {
    Name = local.bus_name
  })
}

resource "aws_cloudwatch_event_archive" "main" {
  name             = "${local.bus_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.main.arn
  retention_days   = var.archive_retention_days
  description      = "Archive de eventos de dominio de ${var.project_name} (${var.environment}) para replay/debug."
}

# DLQ para reglas de EventBridge (target failures). Se crea aunque hoy no
# haya consumidores/reglas registradas (docs/runtime-topology.md de
# 03-backend: "Consumidores actuales: ninguno"), para que este lista cuando
# se agregue el primer consumer.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.bus_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds
  kms_master_key_id         = var.kms_key_arn
  sqs_managed_sse_enabled   = var.kms_key_arn == null ? true : null

  tags = merge(local.common_tags, {
    Name = "${local.bus_name}-dlq"
  })
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeSendMessage"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.dlq.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_bus.main.arn }
        }
      },
    ]
  })
}
