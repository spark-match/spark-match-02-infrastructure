variable "bucket_name" {
  description = "Nombre global del bucket S3. Debe ser unico en todo AWS."
  type        = string
}

variable "versioning_enabled" {
  description = "Activar versionado del bucket."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionales para aplicar al bucket."
  type        = map(string)
  default     = {}
}