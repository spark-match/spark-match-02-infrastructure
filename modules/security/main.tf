###############################################################################
# Module: security
#
# Capa de seguridad perimetral y de identidad para Spark Match (Fase 1):
#   1. KMS CMK por entorno para cifrado de SSM/Secrets/S3/data-at-rest.
#   2. Security groups cross-cutting (lambdas con egress libre, RDS ingress
#      desde sg-lambda, endpoints ingress desde sg-lambda).
#   3. Roles OIDC asumidos por GitHub Actions (uno por dominio + env):
#      - spark-match-sam-deploy-{env}                 (reusable sam-deploy.yml desde 03-backend)
#      - spark-match-bedrock-agentcore-deploy-{env}  (futuro reusable agentcore-deploy.yml desde 08-deep-agent)
#   4. Execution roles cross-service:
#      - spark-match-lambda-runtime-{env}     (asumido por Lambdas)
#      - spark-match-agentcore-runtime-{env}  (asumido por contenedor en AgentCore)
#
# Estrategia multi-env: cada llamada al modulo crea 4 roles para el env
# pasado en var.environment. Los roles OIDC solo aceptan sub claims que
# coincidan con ese env (politica estricta por env), de modo que un token
# de GH emitido para `environment:dev` no puede asumir el role de prod.
#
# Los JSON de politicas viven en ../../docs/policies/*.json (validados contra
# AWS IAM parser en Fase 0) y se adjuntan como inline policies para evitar el
# limite de 6 KB de customer-managed policies.
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

  # Note: los 4 IAM roles (sam_deploy, bedrock_deploy, lambda_runtime, agentcore_runtime)
  # y los policies JSON asociados fueron extraidos a modules/oidc-github en PR4a (Sprint 1).
  # El modulo security ahora solo se encarga de KMS CMK + Security Groups.
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# KMS - Customer Managed Key (CMK) por entorno
###############################################################################

resource "aws_kms_key" "main" {
  description             = "Spark Match CMK for ${var.project_name}/${var.environment} (SSM, Secrets, S3 server-side, logs)"
  is_enabled              = true
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days
  multi_region            = false

  # PR4a (Sprint 1): los 4 IAM roles (sam_deploy, bedrock_deploy, lambda_runtime,
  # agentcore_runtime) se extrajeron a modules/oidc-github. Las dependencies de
  # KMS ahora se manejan via el caller (live/*/main.tf) pasando KMS un `var.kms_role_arns`
  # con los ARNs cross-module, y agregando `oidc_github` module como dependencia.
  # Ref: IMPROVEMENTS.md [B12] / Sprint 1 refactor.

  # Key policy explicita: separa administradores de usuarios de la key.
  # - Administracion (kms:Create*, kms:ScheduleKeyDeletion, kms:PutKeyPolicy):
  #   rol del account root y rol Terraform-{env} (para futuros re-keys/rotations).
  # - Uso (kms:Encrypt, kms:Decrypt, kms:GenerateDataKey*): los 4 roles IAM
  #   del modulo y AWS services (CloudWatch Logs, SSM, Secrets Manager, S3,
  #   Bedrock) que cifran data-at-rest con esta CMK.
  # Ref: IMPROVEMENTS.md [SEC-05]
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "spark-match-${var.environment}-cmk-policy"
    Statement = [
      {
        Sid    = "RootAccountManage"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "TerraformRoleManage"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/spark-match-terraform-plan-${var.environment}",
            "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/spark-match-terraform-apply-${var.environment}",
          ]
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMRolesUseCMK"
        Effect = "Allow"
        Principal = {
          AWS = var.kms_user_role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
      {
        Sid    = "AWSServicesUseCMK"
        Effect = "Allow"
        Principal = {
          Service = [
            "logs.${data.aws_partition.current.dns_suffix}",
            "ssm.${data.aws_partition.current.dns_suffix}",
            "secretsmanager.${data.aws_partition.current.dns_suffix}",
            "s3.${data.aws_partition.current.dns_suffix}",
            "bedrock.${data.aws_partition.current.dns_suffix}",
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}-main"
  target_key_id = aws_kms_key.main.key_id
}

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

