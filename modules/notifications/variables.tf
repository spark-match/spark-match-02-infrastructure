variable "project_name" {
  description = "Nombre del proyecto. Usado en tags y para componer nombres."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars)."
  }
}

variable "tags" {
  description = "Tags adicionales que se mergean con los tags comunes del modulo."
  type        = map(string)
  default     = {}
}

###############################################################################
# SNS topic
###############################################################################

variable "topic_name" {
  description = "Nombre del SNS topic para alertas de budget."
  type        = string
  default     = "spark-match-budget-alerts"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,256}$", var.topic_name))
    error_message = "topic_name debe ser alfanumerico, guion o guion bajo (1-256 chars)."
  }
}

variable "email_subscriptions" {
  description = <<-EOT
    Mapa de suscripciones email al SNS topic. Cada entrada representa 1 suscriptor:
      key   = nombre logico del suscriptor (alfanumerico, guion o guion bajo,
              1-64 chars). Es el identificador usado en `for_each` y en
              Terraform resource addresses (ej. email["ahincho"]).
      value = direccion de email real (debe tener formato email valido).

    Cada vez que se agrega una entrada, AWS envia un mail de confirmacion
    al nuevo suscriptor. Limitacion de SNS: las suscripciones email no se
    pueden auto-confirmar.
  EOT
  type        = map(string)

  validation {
    condition     = length(var.email_subscriptions) > 0
    error_message = "email_subscriptions no puede estar vacio (debe haber al menos 1)."
  }

  validation {
    condition     = alltrue([for k, _ in var.email_subscriptions : can(regex("^[a-zA-Z0-9_-]{1,64}$", k))])
    error_message = "Las keys de email_subscriptions deben ser alfanumericas, guion o guion bajo (1-64 chars)."
  }

  validation {
    condition     = alltrue([for e in values(var.email_subscriptions) : can(regex("^[^@]+@[^@]+\\.[^@]+$", e))])
    error_message = "Todos los values de email_subscriptions deben tener formato email valido."
  }
}

###############################################################################
# AWS Budget
###############################################################################

variable "budget_name" {
  description = "Nombre del AWS Budget."
  type        = string
  default     = "spark-match-monthly-total"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,100}$", var.budget_name))
    error_message = "budget_name debe ser alfanumerico, guion o guion bajo (1-100 chars)."
  }
}

variable "budget_limit_amount" {
  description = "Limite mensual del budget en USD. Default 200 (cubierto por el free tier SNS)."
  type        = number
  default     = 200

  validation {
    condition     = var.budget_limit_amount > 0
    error_message = "budget_limit_amount debe ser positivo."
  }
}

# Outputs que este modulo expone para debugging/auditoria:
# - topic_arn
# - topic_name
# - budget_name
# - subscription_endpoints (lista de emails subscriptos)