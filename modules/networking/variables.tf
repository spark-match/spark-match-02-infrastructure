variable "vpc_name" {
  description = "Nombre logico de la VPC (usado como prefijo en tags y nombres)."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloque CIDR principal de la VPC. Ejemplo: 10.0.0.0/16."
  type        = string
}

variable "azs" {
  description = "Lista de Availability Zones donde crear las subnets. Se esperan 2."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Lista de CIDRs para las subnets publicas (una por AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Lista de CIDRs para las subnets privadas (una por AZ)."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Si true, crea un NAT Gateway para que las subnets privadas tengan salida a Internet."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Mapa de tags comunes aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}