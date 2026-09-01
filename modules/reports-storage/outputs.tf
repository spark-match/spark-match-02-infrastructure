output "bucket_name" {
  description = "Nombre del bucket de informes. Es lo que se publica en SSM (/spark-match/{env}/config/reports-bucket) para que 03-backend y 07-deep-agent no lo hardcodeen."
  value       = aws_s3_bucket.reports.id
}

output "bucket_arn" {
  description = "ARN del bucket de informes. Util para construir las policies de los roles que leen y escriben en el."
  value       = aws_s3_bucket.reports.arn
}

output "bucket_regional_domain_name" {
  description = "Dominio regional del bucket."
  value       = aws_s3_bucket.reports.bucket_regional_domain_name
}

output "access_logs_bucket_arn" {
  description = "ARN del bucket que recibe los server access logs de los informes."
  value       = aws_s3_bucket.access_logs.arn
}
