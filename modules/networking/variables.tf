variable "project_name" {
  description = "Nombre del proyecto."
  type        = string
  default     = "spark-match"
}

variable "environment" {
  description = "Entorno (dev, staging, prod)."
  type        = string
  default     = "prod"
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
}

variable "azs" {
  description = "Lista de AZs donde crear subnets (1 por subnet privada + 1 por subnet publica)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subnets publicas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subnets privadas, una por AZ, en orden."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
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

# Outputs que este modulo expone para que callers (modules/endpoints,
# modules/security) los consuman:
# - vpc_id, public_subnet_ids, private_subnet_ids
# - private_route_table_ids (para el S3 gateway endpoint)
