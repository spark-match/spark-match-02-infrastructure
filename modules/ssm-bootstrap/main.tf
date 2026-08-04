###############################################################################
# Module: ssm-bootstrap
#
# Los 8 parametros SSM que forman el contrato cross-repo con
# spark-match-03-backend (ver docs/adr/0002-cross-repo-config-contract-ssm-secrets.md).
# Este modulo NO calcula nada: recibe los valores ya resueltos (ARNs, nombre
# de tabla, IDs de red, etc.) como variables, que el caller (live/{env}/main.tf)
# pasa desde los outputs de modules/rds-postgres, modules/secrets-bootstrap,
# modules/eventbridge-bus, modules/dynamodb-idempotency, modules/networking
# y modules/security-groups.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "ssm-bootstrap"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  prefix = "/${var.project_name}/${var.environment}/config"
}

# Los siguientes 5 parametros son ARNs / identificadores, NO secretos: un ARN
# que apunta a un secret no es en si mismo sensible (mismo principio que
# `vars.AWS_APPLY_ROLE_ARN` en GitHub Actions). Solo db_connection_url (mas
# abajo) contiene un password embebido y por eso es SecureString.

resource "aws_ssm_parameter" "eventbridge_bus_arn" {
  # checkov:skip=CKV_AWS_337:valor es un ARN/identificador, no un secreto; db_connection_url (abajo) SI usa SecureString.
  name  = "${local.prefix}/eventbridge-bus-arn"
  type  = "String"
  value = var.eventbridge_bus_arn
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "db_secret_arn" {
  # checkov:skip=CKV_AWS_337:valor es un ARN/identificador, no un secreto.
  name  = "${local.prefix}/db-secret-arn"
  type  = "String"
  value = var.db_secret_arn
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "jwt_secret_arn" {
  # checkov:skip=CKV_AWS_337:valor es un ARN/identificador, no un secreto.
  name  = "${local.prefix}/jwt-secret-arn"
  type  = "String"
  value = var.jwt_secret_arn
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "idempotency_table" {
  # checkov:skip=CKV_AWS_337:valor es un nombre de tabla, no un secreto.
  name  = "${local.prefix}/idempotency-table"
  type  = "String"
  value = var.idempotency_table_name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "cors_allowed_origins" {
  # checkov:skip=CKV_AWS_337:valor es una lista de origenes CORS publica, no un secreto.
  name  = "${local.prefix}/cors-allowed-origins"
  type  = "String"
  value = var.cors_allowed_origins
  tags  = local.common_tags
}

# db_connection_url SI contiene un password embebido (postgres://user:pass@host/db)
# -- se cifra con SecureString + la CMK del proyecto.
resource "aws_ssm_parameter" "db_connection_url" {
  name   = "${local.prefix}/db-connection-url"
  type   = "SecureString"
  value  = var.db_connection_url
  key_id = var.kms_key_arn
  tags   = local.common_tags
}

# Los siguientes 2 parametros son IDs de red (subnets, security group), NO
# secretos: el backend los necesita para configurar el VpcConfig de sus
# Lambdas, que corren dentro de la VPC para llegar a RDS (ver ADR 0002 seccion 4).

resource "aws_ssm_parameter" "private_subnet_ids" {
  # checkov:skip=CKV_AWS_337:valor es una lista de subnet IDs, no un secreto.
  name  = "${local.prefix}/private-subnet-ids"
  type  = "String"
  value = join(",", var.private_subnet_ids)
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "lambda_security_group_id" {
  # checkov:skip=CKV_AWS_337:valor es un security group ID, no un secreto.
  name  = "${local.prefix}/lambda-security-group-id"
  type  = "String"
  value = var.lambda_security_group_id
  tags  = local.common_tags
}
