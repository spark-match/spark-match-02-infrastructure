variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno. Determina el identifier de la instancia y el nombre del secret de credenciales."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "private_subnet_ids" {
  description = "IDs de subnets privadas (2+, en AZs distintas) para el DB subnet group. Output de modules/networking."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "RDS requiere un DB subnet group con al menos 2 subnets en AZs distintas."
  }
}

variable "rds_security_group_id" {
  description = "ID del security group de RDS (output de modules/security-groups; permite ingress 5432 desde sg-lambda)."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.rds_security_group_id))
    error_message = "rds_security_group_id debe tener formato sg-<hex>."
  }
}

variable "kms_key_arn" {
  description = "ARN de la CMK de KMS para cifrar storage de RDS y los secrets. Si null, usa la key default administrada por AWS."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

variable "engine_version" {
  description = "Version de PostgreSQL. Fijar una version concreta (no solo el major) evita drift entre lo declarado y lo que AWS reporta tras la creacion."
  type        = string
  default     = "17.4"
}

variable "instance_class" {
  description = "Clase de instancia RDS. db.t4g.micro es free-tier eligible (750h/mes, primeros 12 meses de la cuenta)."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Storage inicial en GB. 20GB es el limite del free-tier de RDS."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage_gb >= 20
    error_message = "allocated_storage_gb debe ser >= 20 (minimo soportado por RDS Postgres)."
  }
}

variable "max_allocated_storage_gb" {
  description = "Limite de autoscaling de storage. 0 (o cualquier valor <= allocated_storage_gb) desactiva el autoscaling -- recomendado en dev para permanecer en el limite del free-tier."
  type        = number
  default     = 0
}

variable "db_name" {
  description = "Nombre de la base de datos inicial creada dentro de la instancia."
  type        = string
  default     = "spark_match"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.db_name))
    error_message = "db_name debe ser un identificador Postgres valido (letra/underscore inicial, alfanumerico despues, max 63 chars)."
  }
}

variable "master_username" {
  description = "Usuario administrador de la instancia RDS."
  type        = string
  default     = "spark_match_admin"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username debe ser un identificador Postgres valido."
  }
}

variable "multi_az" {
  description = "Si desplegar en Multi-AZ (standby en otra AZ, failover automatico). false en dev (Multi-AZ esta fuera del free-tier); true recomendado en prod."
  type        = bool
  default     = false
}

variable "backup_retention_period_days" {
  description = "Dias de retencion de backups automaticos."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period_days >= 1 && var.backup_retention_period_days <= 35
    error_message = "backup_retention_period_days debe estar entre 1 y 35."
  }
}

variable "backup_window" {
  description = "Ventana horaria UTC para backups automaticos (formato hh24:mi-hh24:mi)."
  type        = string
  default     = "07:00-08:00"
}

variable "maintenance_window" {
  description = "Ventana horaria UTC para mantenimiento (formato ddd:hh24:mi-ddd:hh24:mi)."
  type        = string
  default     = "sun:08:30-sun:09:30"
}

variable "deletion_protection" {
  description = "Si proteger la instancia contra terraform destroy / aws rds delete-db-instance. false en dev (permite destroy rapido); true recomendado en prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Si omitir el snapshot final al destruir la instancia. true en dev (destroy rapido, sin costo de snapshot); false recomendado en prod."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Si habilitar Performance Insights (gratis con 7 dias de retencion en instancias soportadas, incluido db.t4g.micro)."
  type        = bool
  default     = false
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Tipos de log de Postgres a exportar a CloudWatch Logs (ej: [\"postgresql\", \"upgrade\"]). Vacio por default para minimizar costo en dev."
  type        = list(string)
  default     = []
}

variable "apply_immediately" {
  description = "Si aplicar cambios de inmediato en vez de esperar la maintenance window. true en dev (iteracion rapida); false recomendado en prod."
  type        = bool
  default     = true
}

variable "secret_recovery_window_in_days" {
  description = "Dias de gracia antes de borrar definitivamente el secret de credenciales tras un delete. 0 = borrado inmediato (solo recomendable en dev)."
  type        = number
  default     = 30

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days debe ser 0 o estar entre 7 y 30."
  }
}
