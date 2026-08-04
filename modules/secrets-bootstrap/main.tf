###############################################################################
# Module: secrets-bootstrap
#
# Secret JWT (HS256) para spark-match-03-backend. El secret de credenciales
# de RDS vive en modules/rds-postgres (necesita el endpoint/puerto de la
# instancia, ver docs/adr/0002-cross-repo-config-contract-ssm-secrets.md).
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "secrets-bootstrap"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  secret_name = "${var.project_name}-${var.environment}-jwt-secret"
}

# 48 bytes aleatorios codificados en base64 (equivalente a
# `openssl rand -base64 48`, ver 03-backend/docs/runbook.md "Rotacion de
# secretos"). La libreria jose (HS256) del backend usa el string completo
# como HMAC key; no necesita ser bytes crudos, un string largo con
# suficiente entropia basta.
resource "random_id" "jwt_secret" {
  byte_length = 48
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = local.secret_name
  description             = "HS256 signing secret para JWTs emitidos por spark-match-03-backend (${var.environment})."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = local.secret_name
  })
}

# `ignore_changes` en secret_string: la rotacion de este secret es manual
# (ver 03-backend/docs/runbook.md §5). Un `terraform apply` normal no debe
# regenerar el valor y de paso invalidar todos los JWTs vigentes (TTL 24h).
# La rotacion real crea una nueva version AWSCURRENT fuera de Terraform.
resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_id.jwt_secret.b64_std

  lifecycle {
    ignore_changes = [secret_string]
  }
}
