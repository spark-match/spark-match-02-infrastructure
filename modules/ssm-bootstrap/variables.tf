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

variable "lambda_security_group_id" {
  description = "ID del security group de Lambda (output de modules/security-groups). El backend lo necesita para el VpcConfig de sus Lambdas."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.lambda_security_group_id))
    error_message = "lambda_security_group_id debe tener formato sg-<hex>."
  }
}
