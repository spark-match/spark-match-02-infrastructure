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

  policies_dir = "${path.module}/../../docs/policies"

  # Sub claim patterns ESTRICTOS por env: el role de X-env solo acepta tokens
  # emitidos para X-env. Asi, spark-match-sam-deploy-dev NO puede ser
  # asumido por un workflow que apunte a environment:prod en el sub claim.
  sam_deploy_sub_patterns = flatten([
    for repo in var.sam_deploy_github_repos : [
      "repo:${repo}:ref:refs/heads/dev",
      "repo:${repo}:ref:refs/heads/main",
      "repo:${repo}:environment:${var.environment}",
    ]
  ])

  bedrock_deploy_sub_patterns = flatten([
    for repo in var.bedrock_deploy_github_repos : [
      "repo:${repo}:ref:refs/heads/dev",
      "repo:${repo}:ref:refs/heads/main",
      "repo:${repo}:environment:${var.environment}",
    ]
  ])
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

###############################################################################
# KMS - Customer Managed Key (CMK) por entorno
###############################################################################

resource "aws_kms_key" "main" {
  description             = "Spark Match CMK for ${var.project_name}/${var.environment} (SSM, Secrets, S3 server-side, logs)"
  is_enabled              = true
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days
  multi_region            = false

  tags = local.common_tags
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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-lambda-${var.environment}"
  })

  lifecycle {
    ignore_changes = [description]
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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-rds-${var.environment}"
  })
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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-endpoints-${var.environment}"
  })
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

###############################################################################
# Roles OIDC asumidos desde GitHub Actions
###############################################################################
#
# Trust policy limitada por repo + branch + environment via el 'sub' claim del
# token OIDC. Detalles completos y diagrama en docs/IAM_ROLES.md.
#
# Estrategia: cada role es por env. Cuando este modulo se invoca con
# environment="dev", crea spark-match-sam-deploy-dev. Cuando se invoca con
# environment="prod", crea spark-match-sam-deploy-prod. Asi el caller
# (live/dev/main.tf o live/prod/main.tf) controla que role asume segun el env.
###############################################################################

# -----------------------------------------------------------------------------
# spark-match-sam-deploy-{env} (reusable sam-deploy.yml desde 03-backend)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sam_deploy" {
  name                 = "${var.project_name}-sam-deploy-${var.environment}"
  description          = "Role asumido por spark-match-03-backend para deploy SAM en ${var.environment} (CloudFormation, Lambda, API GW, EventBridge). Ver docs/IAM_ROLES.md."
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.sam_deploy_sub_patterns
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Inline policy (~9.8 KB) -- excede limite de 6 KB de managed policy.
# Usa templatefile() para interpolar ${environment} desde la policy por env.
resource "aws_iam_role_policy" "sam_deploy_inline" {
  name = "SamDeployPolicy"
  role = aws_iam_role.sam_deploy.id
  policy = templatefile("${local.policies_dir}/${var.environment}/spark-match-sam-deploy.json", {
    environment = var.environment
  })
}

# -----------------------------------------------------------------------------
# spark-match-bedrock-agentcore-deploy-{env} (08-deep-agent)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "bedrock_deploy" {
  name                 = "${var.project_name}-bedrock-agentcore-deploy-${var.environment}"
  description          = "Role asumido por spark-match-08-deep-agent para docker build+push a ECR y agentcore deploy en ${var.environment}. Ver docs/IAM_ROLES.md."
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.bedrock_deploy_sub_patterns
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "bedrock_deploy_inline" {
  name = "BedrockAgentCoreDeployPolicy"
  role = aws_iam_role.bedrock_deploy.id
  policy = templatefile("${local.policies_dir}/${var.environment}/spark-match-bedrock-agentcore-deploy.json", {
    environment = var.environment
  })
}

###############################################################################
# Execution roles (asumidos por Lambdas y por el contenedor de AgentCore)
###############################################################################

# -----------------------------------------------------------------------------
# spark-match-lambda-runtime-{env}
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "lambda_runtime" {
  name                 = "${var.project_name}-lambda-runtime-${var.environment}"
  description          = "Execution role para Lambdas spark-match-backend-* en ${var.environment}. Logs + X-Ray + SSM + Secrets + Events + DDB + KMS."
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_runtime.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_runtime.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray_daemon" {
  role       = aws_iam_role.lambda_runtime.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "lambda_runtime_inline" {
  name = "LambdaRuntimePolicy"
  role = aws_iam_role.lambda_runtime.id
  policy = templatefile("${local.policies_dir}/${var.environment}/spark-match-lambda-runtime.json", {
    environment = var.environment
  })
}

# -----------------------------------------------------------------------------
# spark-match-agentcore-runtime-{env}
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "agentcore_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = [
        "bedrock-agentcore.amazonaws.com",
        "ecs-tasks.amazonaws.com",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "agentcore_runtime" {
  name                 = "${var.project_name}-agentcore-runtime-${var.environment}"
  description          = "Execution role para el contenedor FastAPI del agente en Bedrock AgentCore (${var.environment}). Bedrock InvokeModel + Secrets + SSM + RDS-data + KMS."
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.agentcore_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "agentcore_cw_agent" {
  role       = aws_iam_role.agentcore_runtime.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "agentcore_xray_daemon" {
  role       = aws_iam_role.agentcore_runtime.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "agentcore_runtime_inline" {
  name = "AgentCoreRuntimePolicy"
  role = aws_iam_role.agentcore_runtime.id
  policy = templatefile("${local.policies_dir}/${var.environment}/spark-match-agentcore-runtime.json", {
    environment = var.environment
  })
}
