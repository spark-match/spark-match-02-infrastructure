###############################################################################
# Module: dynamodb-idempotency
#
# Tabla DynamoDB para AWS Lambda Powertools Idempotency
# (@aws-lambda-powertools/idempotency, DynamoDBPersistenceLayer). Schema
# minimo compatible con los defaults de Powertools: hash key "id" + TTL
# "expiration". Las demas keys (status, data, validation) son atributos
# libres que DynamoDB no necesita declarar (schemaless fuera de las keys).
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "dynamodb-idempotency"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  table_name = "${var.project_name}-${var.environment}-idempotency"
}

resource "aws_dynamodb_table" "idempotency" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "expiration"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = merge(local.common_tags, {
    Name = local.table_name
  })
}
