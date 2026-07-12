variable "project_name" {
  description = "Nombre del proyecto."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars)."
  }
}

variable "environment" {
  description = "Entorno (dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags adicionales."
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "Region AWS. Necesaria para componer los service_name de los VPC endpoints."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR principal de la VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR valido (ej. 10.0.0.0/16)."
  }
}

variable "azs" {
  description = "Lista de AZs donde crear subnets (1 por subnet privada + 1 por subnet publica)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) >= 1 && length(var.azs) <= 3
    error_message = "azs debe tener entre 1 y 3 elementos."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subnets publicas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs debe tener la misma cantidad de elementos que azs."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Todos los public_subnet_cidrs deben ser CIDRs validos."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subnets privadas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs debe tener la misma cantidad de elementos que azs."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Todos los private_subnet_cidrs deben ser CIDRs validos."
  }
}

variable "enable_nat_gateway" {
  description = "Si crear NAT Gateway(s) para que las subnets privadas tengan salida a internet. False util para dev offline."
  type        = bool
  default     = true
}

variable "enable_nat_ha" {
  description = "Si crear un NAT por AZ (HA). Si false, 1 NAT compartido en la primera subnet publica. Costo extra ~$35/mes si true."
  type        = bool
  default     = false
}
