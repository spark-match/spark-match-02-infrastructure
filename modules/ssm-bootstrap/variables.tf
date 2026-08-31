variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los paths SSM."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno. Determina el prefijo /spark-match/{env}/config/ (aislamiento dev/prod en la misma cuenta AWS)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a los parametros."
  type        = map(string)
  default     = {}
}

variable "eventbridge_bus_arn" {
  description = "ARN del bus de EventBridge (output de modules/eventbridge-bus)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:events:", var.eventbridge_bus_arn))
    error_message = "eventbridge_bus_arn debe ser un ARN valido de EventBridge."
  }
}

variable "db_secret_arn" {
  description = "ARN del secret de credenciales de RDS (output de modules/rds-postgres)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:secretsmanager:", var.db_secret_arn))
    error_message = "db_secret_arn debe ser un ARN valido de Secrets Manager."
  }
}

variable "jwt_secret_arn" {
  description = "ARN del secret JWT (output de modules/secrets-bootstrap)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:secretsmanager:", var.jwt_secret_arn))
    error_message = "jwt_secret_arn debe ser un ARN valido de Secrets Manager."
  }
}

variable "db_connection_url" {
  description = "Connection URL completa de Postgres (postgres://user:pass@host:port/db), output SENSITIVE de modules/rds-postgres. Se almacena como SecureString."
  type        = string
  sensitive   = true
}

variable "idempotency_table_name" {
  description = "Nombre de la tabla DynamoDB de idempotencia (output de modules/dynamodb-idempotency)."
  type        = string
}

variable "cors_allowed_origins" {
  description = "Origenes CORS permitidos, comma-separated. '*' en dev, lista explicita de dominios en prod."
  type        = string
  default     = "*"
}

variable "kms_key_arn" {
  description = "ARN de la CMK para cifrar el parametro SecureString (db_connection_url). Si null, usa la key default administrada por AWS (alias/aws/ssm)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

variable "private_subnet_ids" {
  description = "IDs de subnets privadas (output de modules/networking). El backend las necesita para el VpcConfig de sus Lambdas (corren dentro de la VPC para llegar a RDS). Se almacena como CSV en un solo parametro String."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "private_subnet_ids debe tener al menos 1 elemento."
  }
}

variable "reports_bucket_name" {
  description = "Nombre del bucket de informes de orientacion (output de modules/reports-storage). Se publica en SSM para que 03-backend y 08-deep-agent no lo hardcodeen."
  type        = string
}

variable "reports_max_per_user_per_day" {
  description = "Cuantos informes puede generar un mismo estudiante al dia. Cada generacion es una llamada al LLM mas un render de PDF, asi que es un tope de coste ademas de uno de abuso. Independiente del cap diario de peticiones al agente (SPARK_BUDGET_MAX_REQUESTS_PER_USER_PER_DAY): son unidades distintas y un informe cuesta mucho mas que un turno de chat."
  type        = number
  default     = 3

  validation {
    condition     = var.reports_max_per_user_per_day >= 1
    error_message = "reports_max_per_user_per_day debe ser >= 1."
  }
}

variable "reports_min_profile_completeness" {
  description = "Completitud minima del StudentProfile para poder emitir un informe (0.0-1.0). El default 0.6 sale de como reparte puntos `StudentProfile.profile_completeness`: 12 en total, 9 campos mas hasta 3 intereses. Solo el RIASEC da 0.50, asi que 0.60 exige RIASEC mas dos campos de contexto. Es la puerta blanda del ADR-019 D8; la dura (tener las seis puntuaciones RIASEC) no es configurable porque sin ellas el motor no tiene entrada."
  type        = number
  default     = 0.6

  validation {
    condition     = var.reports_min_profile_completeness >= 0 && var.reports_min_profile_completeness <= 1
    error_message = "reports_min_profile_completeness debe estar entre 0.0 y 1.0."
  }
}

variable "lambda_security_group_id" {
  description = "ID del security group de Lambda (output de modules/security-groups). El backend lo necesita para el VpcConfig de sus Lambdas."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.lambda_security_group_id))
    error_message = "lambda_security_group_id debe tener formato sg-<hex>."
  }
}
