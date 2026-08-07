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

  # CloudWatch Logs es la excepcion: cuando cifra un log group con una CMK llama
  # a KMS con el principal CALIFICADO POR REGION (logs.us-east-1.amazonaws.com),
  # no con el global. Con el global, KMS no reconoce al llamante y CreateLogGroup
  # falla con "The specified KMS key does not exist or is not allowed to be used
  # with Arn 'arn:aws:logs:...'", que es engañoso: la key existe y el permiso IAM
  # esta; lo que no matchea es el principal del key policy.
  #
  # Estuvo latente hasta ahora porque ningun log group usaba la CMK (los 12 de
  # las Lambdas del backend tienen kmsKeyId=None). El del agente en Fargate es el
  # primero que lo intenta.
  #
  # Ref: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html
  # Ademas del principal regional, Logs necesita su propia condicion. Por eso
  # sale del statement generico y tiene el suyo (`CloudWatchLogsUseCMK`, mas
  # abajo): el resto de los servicios se autoriza por kms:CallerAccount, que
  # Logs no satisface.
  services_with_own_statement = ["logs"]

  # Los demas servicios usan el principal global y el statement compartido.
  service_principal_arns = [
    for svc in var.aws_service_principals :
    "${svc}.${data.aws_partition.current.dns_suffix}"
    if !contains(local.services_with_own_statement, svc)
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

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
      {
        # CloudWatch Logs va en su propio statement porque NO satisface la
        # condicion kms:CallerAccount del statement anterior. Los otros 7
        # servicios llaman a KMS arrastrando el contexto del caller que creo el
        # recurso, asi que kms:CallerAccount viene poblado (verificado: RDS,
        # Secrets Manager y DynamoDB cifran con esta CMK sin problema). Logs
        # cifra de forma asincrona desde su propio contexto de servicio y la
        # condicion no matchea, con lo cual ningun Allow aplica y KMS deniega.
        #
        # El sintoma es un CreateLogGroup que falla con "The specified KMS key
        # does not exist or is not allowed to be used", incluso con credenciales
        # de admin -- lo que descarta que sea un problema de IAM del caller.
        #
        # La condicion que si corresponde es la documentada por AWS: acotar por
        # el encryption context aws:logs:arn, que limita el uso de la CMK a log
        # groups de esta cuenta y region.
        #
        # Ref: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html
        Sid    = "CloudWatchLogsUseCMK"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"
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
