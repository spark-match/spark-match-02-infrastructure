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
  # checkov:skip=CKV2_AWS_30:query logging (log_statement/log_min_duration_statement) no activado. Exige un parameter group propio y multiplica la ingesta de CloudWatch Logs; el presupuesto de la cuenta es $200/mes. Se puede activar puntualmente para diagnosticar.
  # checkov:skip=CKV_AWS_157:Multi-AZ desactivado. Duplica el coste de la instancia y spark-match es un proyecto de curso sin compromiso de disponibilidad. Decision del mismo orden que rds_backup_retention_period_days=0, documentada en live/prod/terraform.tfvars.
  # checkov:skip=CKV_AWS_293:deletion_protection se controla por ambiente via var.deletion_protection. prod lo activa; dev lo deja en false a proposito para poder recrear el entorno mientras se itera. Checkov escanea el modulo aislado y solo ve el default.
  # checkov:skip=CKV_AWS_353:performance insights desactivado. Tiene coste por instancia y no aporta en un proyecto de curso sin carga real. Mismo criterio de coste que Multi-AZ.
  # checkov:skip=CKV_AWS_161:IAM database authentication no se usa en este POC; auth via password + Secrets Manager (arquitectura ya definida en BACKEND-DEPLOY.md).
  # checkov:skip=CKV_AWS_118:enhanced monitoring (requiere IAM role + costo extra) diferido; Performance Insights disponible via var.performance_insights_enabled.
  # checkov:skip=CKV_AWS_129:log exports a CloudWatch desactivados por default para minimizar costo en dev; activar con var.enabled_cloudwatch_logs_exports si se necesita debug.
  # checkov:skip=CKV_AWS_133:dev usa backup_retention_period_days=0 por restriccion dura de cuenta AWS "Free Tier account" (AWS rechazo CreateDBInstance con FreeTierRestrictionError al pedir 7 dias, confirmado en cuenta 681526276858 el 2026-08-04). prod debe mantener backup_retention_period_days >= 7 via su propio terraform.tfvars; este skip es a nivel de modulo (aplica a cualquier caller) porque el check no puede evaluar el valor real resuelto por entorno.
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
  # Reusa la misma CMK del storage (var.kms_key_arn) para cifrar Performance
  # Insights (CKV_AWS_354). null cuando performance insights esta
  # desactivado (evita pasar un valor sin efecto) o cuando kms_key_arn es
  # null (AWS usa su key administrada por defecto en ese caso).
  performance_insights_kms_key_id = var.performance_insights_enabled ? var.kms_key_arn : null

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
  # checkov:skip=CKV2_AWS_57:rotacion automatica no configurada. Exige una Lambda de rotacion con acceso de red a la instancia RDS, que es un componente de infraestructura entero fuera del alcance actual. La credencial la genera terraform con random_password y no se comparte fuera del secret.
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
