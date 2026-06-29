output "bucket_id" {
  description = "Nombre del bucket creado."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN del bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "Region AWS donde se creo el bucket."
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "Domain name del bucket (formato: <bucket>.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "versioning_enabled" {
  description = "Estado del versionado."
  value       = aws_s3_bucket_versioning.this.versioning_configuration[0].status
}