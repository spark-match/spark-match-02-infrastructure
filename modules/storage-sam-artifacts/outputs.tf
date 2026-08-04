output "bucket_name" {
  description = "Nombre del bucket de artefactos SAM (spark-match-sam-artifacts-{env})."
  value       = aws_s3_bucket.sam_artifacts.id
}

output "bucket_arn" {
  description = "ARN del bucket de artefactos SAM."
  value       = aws_s3_bucket.sam_artifacts.arn
}

output "access_logs_bucket_name" {
  description = "Nombre del bucket que recibe los server access logs del bucket de artefactos."
  value       = aws_s3_bucket.access_logs.id
}
