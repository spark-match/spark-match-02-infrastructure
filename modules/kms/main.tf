locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "kms"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  # Construir los service principals con el suffix DNS correcto (varia por region).
  service_principal_arns = [
    for svc in var.aws_service_principals : "${svc}.${data.aws_partition.current.dns_suffix}"
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# KMS - Customer Managed Key (CMK) por entorno
###############################################################################
# Encrypted resources en ${var.environment}:
#   - SSM parameters (modules/ssm-bootstrap)
#   - Secrets Manager (modules/secrets-bootstrap, modules/rds-postgres)
#   - S3 server-side encryption (modules/storage-sam-artifacts)
#   - CloudWatch Logs (VPC flow logs, RDS logs, Lambda logs)
#   - Bedrock (model invocation responses)
#   - RDS storage encryption (modules/rds-postgres)
#   - DynamoDB table encryption (modules/dynamodb-idempotency)
#   - SQS DLQ encryption (modules/eventbridge-bus)
#
# Key policy explicita con 4 statements:
#   1. RootAccountManage: el account root puede hacer todo (kms:*).
#   2. TerraformRoleManage: los 2 roles spark-match-terraform-{plan,apply}-{env}
#      pueden administrar la CMK (re-keys, rotations, deletions).
#   3. IAMRolesUseCMK: los N roles en var.user_role_arns pueden encrypt/decrypt.
#   4. AWSServicesUseCMK: los 8 service principals pueden encrypt/decrypt (logs,
#      ssm, secretsmanager, s3, bedrock, rds, dynamodb, sqs) con condition
#      kms:CallerAccount para evitar cross-account abuse.
#
# Ref: IMPROVEMENTS.md [SEC-05]
###############################################################################

resource "aws_kms_key" "main" {
  description             = "Spark Match CMK for ${var.project_name}/${var.environment} (SSM, Secrets, S3 server-side, logs)"
  is_enabled              = true
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  multi_region            = false

  # PR4b (Sprint 1): la CMK se movio a modules/kms. Los var.user_role_arns vienen
  # cross-module desde module.oidc_github.*_role_arn. KMS exige que los principals
  # existan al validar la policy, por lo que el caller (live/*/main.tf) debe
  # garantizar el orden via `depends_on = [module.oidc_github].
  # Ref: IMPROVEMENTS.md [B12]

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
          AWS = var.user_role_arns
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
          Service = local.service_principal_arns
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
