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
  description = "Nombre del entorno. Determina nombres de recursos y tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "repository_suffix" {
  description = "Sufijo del nombre del repositorio ECR. El nombre final es `{project_name}-{repository_suffix}-{environment}` (ej. spark-match-agent-advisor-dev), que debe matchear el allowlist IAM `spark-match-agent-*-{env}` de modules/oidc-github/policies/{env}/spark-match-bedrock-agentcore-deploy.json."
  type        = string
  default     = "agent-advisor"

  validation {
    condition     = can(regex("^agent-[a-z0-9-]{1,20}$", var.repository_suffix))
    error_message = "repository_suffix debe empezar con 'agent-' para caer dentro del allowlist IAM `spark-match-agent-*-{env}`."
  }
}

variable "kms_key_arn" {
  description = "ARN de la CMK del proyecto para cifrar las capas de imagen en reposo. Si null, ECR usa AES256 con la key administrada por AWS (gratis). Nota: con KMS, ECR crea un grant sobre la CMK al momento de crear el repositorio, por lo que el rol que hace el apply necesita `kms:CreateGrant` ademas de los permisos de encrypt/decrypt."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

variable "image_tag_mutability" {
  description = "Si los tags de imagen pueden reescribirse. IMMUTABLE por defecto: un tag ya publicado nunca cambia de digest, lo que hace que el rollout a ECS sea reproducible y auditable."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability debe ser IMMUTABLE o MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Si ejecutar el scan de vulnerabilidades basico de ECR al hacer push. Gratis (basic scanning), a diferencia de enhanced scanning via Inspector."
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Cuantas imagenes conservar antes de que la lifecycle policy expire las mas antiguas. 10 por defecto: suficiente para rollback de varias revisiones sin acumular costo de storage."
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count >= 1 && var.max_image_count <= 100
    error_message = "max_image_count debe estar entre 1 y 100."
  }
}

variable "force_delete" {
  description = "Si permitir que `terraform destroy` borre el repositorio aunque contenga imagenes. true en dev (iteracion rapida), false en prod (protege las imagenes que estan corriendo)."
  type        = bool
  default     = false
}
