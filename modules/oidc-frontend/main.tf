locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "oidc-frontend"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  branch    = var.environment == "prod" ? "main" : "dev"
  gh_env    = var.environment == "prod" ? "production" : "development"
  role_name = "${var.project_name}-frontend-deploy-${var.environment}"

  sub_patterns = [
    "repo:${var.repo}@*:ref:refs/heads/${local.branch}",
    "repo:${var.repo}@*:environment:${local.gh_env}",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "frontend_deploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.sub_patterns
    }
  }
}

resource "aws_iam_role" "frontend_deploy" {
  name                 = local.role_name
  description          = "Role asumido por spark-match-04-frontend para deploy de S3 + invalidation de CloudFront en ${var.environment}."
  max_session_duration = var.iam_role_max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.frontend_deploy_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "frontend_deploy_inline" {
  statement {
    sid    = "S3OnFrontendBuckets"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:DeleteObject",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
    ]
    resources = [
      var.bucket_arn,
      "${var.bucket_arn}/*",
      var.access_logs_bucket_arn,
      "${var.access_logs_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
      "cloudfront:GetDistribution",
      "cloudfront:ListDistributions",
    ]
    resources = [var.distribution_arn]
  }
}

resource "aws_iam_role_policy" "frontend_deploy_inline" {
  name   = "FrontendDeployPolicy"
  role   = aws_iam_role.frontend_deploy.id
  policy = data.aws_iam_policy_document.frontend_deploy_inline.json
}
