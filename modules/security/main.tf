###############################################################################
# Module: security
#
# Capa de seguridad perimetral para Spark Match (Fase 1):
#   - 3 Security groups cross-cutting (lambdas con egress libre, RDS ingress
#     desde sg-lambda, endpoints ingress desde sg-lambda).
#
# PR4a (Sprint 1): 4 IAM roles extraidos a modules/oidc-github.
# PR4b (Sprint 1): KMS CMK extraida a modules/kms.
# Este modulo ahora solo contiene los 3 Security Groups.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "security"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# Security groups
###############################################################################

resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-sg-lambda-${var.environment}"
  description = "Security group for AWS Lambda functions in ${var.environment} (egress only)"
  vpc_id      = var.vpc_id

  # Bloque `egress` explicito (vacio) para forzar a Terraform a remover la
  # default egress rule de AWS (que es "allow all 0.0.0.0/0"). Sin esto, las
  # reglas `aws_security_group_rule` se SUMAN al default, no lo reemplazan,
  # dejando un bypass de seguridad.
  # Ref: IMPROVEMENTS.md [A6] [SEC-08]
  egress = []

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-lambda-${var.environment}"
  })

  # `ignore_changes = [egress, ingress]` evita que Terraform intente borrar
  # las reglas de egress/ingress administradas via `aws_security_group_rule`
  # en cada refresh. Sin esto, el provider AWS Terraform v5.x confunde las
  # rules separadas con rules inline del SG y propone removerlas (drift
  # fantasma). Las rules son manejadas por los recursos `aws_security_group_rule`
  # de abajo y el SG solo lleva `egress = []` para neutralizar la default rule
  # de AWS al momento de la creacion.
  # Ref: IMPROVEMENTS.md [B12]
  lifecycle {
    ignore_changes = [description, ingress, egress]
  }
}

resource "aws_security_group_rule" "lambda_egress_vpc" {
  count = var.create_lambda_sg_rules ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  description       = "Allow all egress to VPC CIDR (RDS, Redis, endpoints)"
  security_group_id = aws_security_group.lambda.id
}

resource "aws_security_group_rule" "lambda_egress_internet" {
  count = var.create_lambda_sg_rules ? 1 : 0

  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress for outbound API calls (Bedrock, Tavily, LangSmith)"
  security_group_id = aws_security_group.lambda.id
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-sg-rds-${var.environment}"
  description = "Security group for Aurora PostgreSQL in ${var.environment}"
  vpc_id      = var.vpc_id

  # RDS es un server de base de datos: solo responde a queries entrantes
  # (port 5432 desde sg-lambda). No deberia iniciar conexiones outbound.
  # El default de AWS es "egress allow all 0.0.0.0/0" -- lo removemos para
  # defense in depth. Ref: IMPROVEMENTS.md [A6] [SEC-08]
  egress = []

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-rds-${var.environment}"
  })

  # Ver comentario en aws_security_group.lambda sobre ignore_changes.
  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

resource "aws_security_group_rule" "rds_ingress_from_lambda" {
  count = var.create_rds_sg_rules ? 1 : 0

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  description              = "Allow Postgres traffic from Lambda execution ENIs"
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group" "endpoints" {
  name        = "${var.project_name}-sg-endpoints-${var.environment}"
  description = "Security group for VPC interface endpoints (SSM, Secrets, ECR, Bedrock, KMS, Logs, STS)"
  vpc_id      = var.vpc_id

  # VPC interface endpoints son servicios AWS administrados: solo responden
  # a llamadas HTTPS entrantes (port 443 desde sg-lambda). No deberian iniciar
  # conexiones outbound. Removemos el egress default "allow all" para defense
  # in depth. Ref: IMPROVEMENTS.md [A6] [SEC-08]
  egress = []

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-endpoints-${var.environment}"
  })

  # Ver comentario en aws_security_group.lambda sobre ignore_changes.
  lifecycle {
    ignore_changes = [ingress, egress]
  }
}

resource "aws_security_group_rule" "endpoints_ingress_from_lambda" {
  count = var.create_endpoints_sg_rules ? 1 : 0

  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  description              = "Allow HTTPS to VPC endpoints from Lambdas only"
  security_group_id        = aws_security_group.endpoints.id
}
