locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "oidc-github"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  policies_dir = "${path.module}/policies"

  # Sub claim patterns ESTRICTOS por env: el role de X-env solo acepta tokens
  # emitidos para X-env. Asi, spark-match-sam-deploy-dev NO puede ser
  # asumido por un workflow que apunte a environment:prod en el sub claim.
  #
  # Format: `repo:OWNER@USERID/REPO@REPOID:event` (formato actual de GitHub
  # Actions con numeric IDs; ver AGENTS.md item 4 de "Reglas duras").
  # Usamos `@*` como wildcard para los IDs numericos, lo que matchea tanto
  # para repos privados como publicos. Sin `@*`, los tokens de GH Actions
  # son rechazados por la trust policy.
  #
  # Verificado contra el sub claim emitido por GH Actions:
  #   repo:spark-match@82984150/spark-match-03-backend@1285525572:pull_request
  sam_deploy_sub_patterns = flatten([
    for repo in var.sam_deploy_github_repos : [
      "repo:${repo}@*:ref:refs/heads/dev",
      "repo:${repo}@*:ref:refs/heads/main",
      "repo:${repo}@*:environment:${var.environment}",
    ]
  ])

  bedrock_deploy_sub_patterns = flatten([
    for repo in var.bedrock_deploy_github_repos : [
      "repo:${repo}@*:ref:refs/heads/dev",
      "repo:${repo}@*:ref:refs/heads/main",
      "repo:${repo}@*:environment:${var.environment}",
    ]
  ])
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# OIDC Identity Provider para GitHub Actions
###############################################################################
# SINGLETON a nivel de cuenta AWS. Si ya existe (administrado por otro repo,
# ej. orion-infrastructure), NO se re-crea. La variable create_oidc_provider
# controla si este modulo lo crea o solo lo lee.
#
# URL: https://token.actions.githubusercontent.com
# ClientId: sts.amazonaws.com (audiencia = AWS STS)
# Thumbprints: 2 (viejo + nuevo cert). Ver docs/adr/0001-oidc-thumbprint-rotation.md.
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_provider_thumbprints

  tags = local.common_tags
}

# Data source: lee el OIDC provider existente. Si no existe, falla en plan time
# (lo cual es bueno: si esperamos que exista y no esta, debemos crearlo).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github.arn
}

###############################################################################
# IAM Role: spark-match-sam-deploy-{env} (reusable sam-deploy.yml desde 03-backend)
###############################################################################

data "aws_iam_policy_document" "sam_deploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.sam_deploy_sub_patterns
    }
  }
}

resource "aws_iam_role" "sam_deploy" {
  name                 = "${var.project_name}-sam-deploy-${var.environment}"
  description          = "Role asumido por spark-match-03-backend para deploy SAM en ${var.environment} (CloudFormation, Lambda, API GW, EventBridge). Ver docs/IAM_ROLES.md."
  max_session_duration = var.iam_role_max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.sam_deploy_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "sam_deploy_inline" {
  name = "SamDeployPolicy"
  role = aws_iam_role.sam_deploy.id
  policy = templatefile("${local.policies_dir}/${var.environment}/spark-match-sam-deploy.json", {
    environment = var.environment
  })
}

###############################################################################
# IAM Role: spark-match-bedrock-agentcore-deploy-{env} (08-deep-agent)
###############################################################################

data "aws_iam_policy_document" "bedrock_deploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.bedrock_deploy_sub_patterns
    }
  }
}

resource "aws_iam_role" "bedrock_deploy" {
  name                 = "${var.project_name}-bedrock-agentcore-deploy-${var.environment}"
  description          = "Role asumido por spark-match-08-deep-agent para docker build+push a ECR y agentcore deploy en ${var.environment}. Ver docs/IAM_ROLES.md."
  max_session_duration = var.iam_role_max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.bedrock_deploy_assume_role.json

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
  max_session_duration = var.iam_role_max_session_duration
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
  max_session_duration = var.iam_role_max_session_duration
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
