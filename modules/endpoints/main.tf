###############################################################################
# Module: endpoints
#
# VPC Endpoints de Spark Match (Fase 1):
#   - Interface endpoints: ssm, ssmmessages, ec2messages, secretsmanager, kms,
#     logs, ecr.api, ecr.dkr, bedrock-runtime, sts
#   - Gateway endpoint: s3 (gratis, recomendado siempre)
#
# Por que existen: las Lambdas y el contenedor FastAPI en subnets privadas no
# deben hacer every-API-call salir por NAT. Con VPC endpoints:
#   - SSM agent: <5 ms (necesario para configurar runtime)
#   - ECR pull: -1.5 s en cold start (vs 4-6 s atravesando NAT)
#   - CloudWatch Logs: ingest rapido sin cargo de NAT
#   - Bedrock InvokeModel: baja latencia para streaming SSE del agente
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "endpoints"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  # Map nombre_corto -> nombre de servicio en la API
  interface_endpoint_services = {
    "ssm"             = "ssm"
    "ssmmessages"     = "ssmmessages"
    "ec2messages"     = "ec2messages"
    "secretsmanager"  = "secretsmanager"
    "kms"             = "kms"
    "logs"            = "logs"
    "ecr.api"         = "ecr.api"
    "ecr.dkr"         = "ecr.dkr"
    "bedrock-runtime" = "bedrock-runtime"
    "sts"             = "sts"
  }

  enabled_interface_endpoints = var.enable_all_endpoints_by_default ? toset(keys(local.interface_endpoint_services)) : toset(var.enabled_endpoints)
}

# -----------------------------------------------------------------------------
# Interface endpoints
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "interface" {
  for_each = local.enabled_interface_endpoints

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${local.interface_endpoint_services[each.key]}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  private_dns_enabled = true
  security_group_ids  = [var.endpoints_security_group_id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# Gateway endpoint para S3 (gratis)
# -----------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-s3"
  })
}
