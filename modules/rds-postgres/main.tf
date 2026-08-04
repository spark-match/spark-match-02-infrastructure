###############################################################################
# Module: rds-postgres
#
# Instancia RDS PostgreSQL (Single-AZ, db.t4g.micro free-tier eligible en
# los primeros 12 meses) para spark-match-03-backend. NO usa Aurora: decision
# documentada (BACKEND-DEPLOY.md v6) de mantenerse en free-tier para un POC.
#
# Este modulo tambien crea y posee el secret de credenciales de conexion
# (spark-match-{env}-db-credentials, JSON {host, port, database, username,
# password}), porque necesita el endpoint/puerto de la instancia recien
# creada -- separar el secret en modules/secrets-bootstrap forzaria un
# acoplamiento cross-module mas fragil. Ver docs/adr/0002.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "rds-postgres"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  identifier         = "${var.project_name}-${var.environment}-db"
  db_credentials_arn = "${var.project_name}-${var.environment}-db-credentials"

  connection_url = "postgres://${var.master_username}:${urlencode(random_password.master.result)}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}"
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Subnets privadas para RDS de ${var.project_name} (${var.environment})."
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

# Password maestro generado y gestionado por Terraform (no usa
# `manage_master_user_password` de RDS porque ese modo solo produce un
# secret con {username, password}, y el backend espera un secret unico con
# {host, port, database, username, password} combinados).
resource "random_password" "master" {
  length = 32
  # Excluye caracteres problematicos en connection strings / JSON / shell:
  # mantiene solo un set seguro de simbolos.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "main" {
  # checkov:skip=CKV_AWS_161:IAM database authentication no se usa en este POC; auth via password + Secrets Manager (arquitectura ya definida en BACKEND-DEPLOY.md).
  # checkov:skip=CKV_AWS_118:enhanced monitoring (requiere IAM role + costo extra) diferido; Performance Insights disponible via var.performance_insights_enabled.
  # checkov:skip=CKV_AWS_129:log exports a CloudWatch desactivados por default para minimizar costo en dev; activar con var.enabled_cloudwatch_logs_exports si se necesita debug.
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb > var.allocated_storage_gb ? var.max_allocated_storage_gb : null
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  multi_az               = var.multi_az
  publicly_accessible    = false

  backup_retention_period = var.backup_retention_period_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.identifier}-final"

  auto_minor_version_upgrade   = true
  performance_insights_enabled = var.performance_insights_enabled

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  apply_immediately = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = local.identifier
  })

  # La rotacion del password es manual (ver 03-backend/docs/runbook.md §5):
  # un `terraform apply` normal no debe resetear el password vigente.
  lifecycle {
    ignore_changes = [password]
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = local.db_credentials_arn
  description             = "Credenciales de conexion a RDS Postgres para spark-match-03-backend (${var.environment})."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = local.db_credentials_arn
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    database = aws_db_instance.main.db_name
    username = aws_db_instance.main.username
    password = random_password.master.result
  })

  # Igual que el password de la instancia: rotacion manual, no automatica
  # en cada apply. Rotacion real (Sprint futuro) via
  # aws_secretsmanager_secret_rotation, ver docs/adr/0002.
  lifecycle {
    ignore_changes = [secret_string]
  }
}
