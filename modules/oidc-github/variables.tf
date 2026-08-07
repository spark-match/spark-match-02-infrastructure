variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de roles IAM."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno. Determina nombres de recursos, trust policies OIDC y tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "github_environment_name" {
  description = "Nombre del GitHub Environment que los callers usan en el sub claim (`repo:OWNER/REPO:environment:NAME`). Por defecto igual a `environment`, pero en prod el GH Environment real se llama 'production' mientras que `environment` (usado para nombrar recursos AWS) es 'prod' -- deben poder divergir."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}

variable "sam_deploy_github_repos" {
  description = "Repos GitHub permitidos en el trust policy de spark-match-sam-deploy. Sub claim patterns se derivan automaticamente."
  type        = list(string)
  default     = ["spark-match/spark-match-03-backend"]

  validation {
    condition     = length(var.sam_deploy_github_repos) > 0
    error_message = "sam_deploy_github_repos no puede estar vacio."
  }
}

variable "bedrock_deploy_github_repos" {
  description = "Repos GitHub permitidos en el trust policy de spark-match-bedrock-agentcore-deploy."
  type        = list(string)
  default     = ["spark-match/spark-match-08-deep-agent"]

  validation {
    condition     = length(var.bedrock_deploy_github_repos) > 0
    error_message = "bedrock_deploy_github_repos no puede estar vacio."
  }
}

variable "iam_role_max_session_duration" {
  description = "Duracion maxima de la sesion (en segundos) para los 4 roles IAM creados por este modulo. AWS solo acepta el rango 3600-43200 (1h-12h). Default 3600 (1h). Para reducir el blast radius en eventos de compromise, considerar SCP que fuerce sts:AssumeRole + sts:TagSession en OIDC a tener un `MaxSessionDuration` corto via el role chaining."
  type        = number
  default     = 3600

  validation {
    condition     = var.iam_role_max_session_duration >= 3600 && var.iam_role_max_session_duration <= 43200
    error_message = "iam_role_max_session_duration debe estar entre 3600 (1h) y 43200 (12h). AWS rechaza valores fuera de este rango."
  }
}

variable "oidc_provider_thumbprints" {
  description = "Thumbprints SHA-1 de los certificados del OIDC provider de GitHub Actions (token.actions.githubusercontent.com). GitHub rota certificados; mantener ambos durante la transicion. Default incluye el cert estable desde 2023 + el nuevo cert de 2026. Ver docs/adr/0001-oidc-thumbprint-rotation.md."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # estable desde 2023
    "a6840fac8d59c1b2737d22c4dd2d7485b69e9b8e", # nuevo cert, 2026
  ]

  validation {
    condition     = length(var.oidc_provider_thumbprints) >= 1
    error_message = "oidc_provider_thumbprints no puede estar vacio."
  }
}

variable "create_oidc_provider" {
  description = "Si crear el aws_iam_openid_connect_provider. Default false porque actualmente el OIDC provider es un SINGLETON a nivel de cuenta AWS y esta siendo administrado por orion-infrastructure (misma cuenta 681526276858). Cuando orion se decommisione, flip a true para que spark-match-02-infrastructure lo adopte. La thumbprint_list se valida contra el provider existente en plan time via data source."
  type        = bool
  default     = false
}
