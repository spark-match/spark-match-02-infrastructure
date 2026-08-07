output "frontend_bucket_arn" {
  description = "ARN del bucket S3 que almacena los assets del frontend."
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_name" {
  description = "Nombre del bucket S3 (spark-match-frontend-{env})."
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_regional_domain_name" {
  description = "Domain name regional del bucket S3 (para endpoint regional)."
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "frontend_distribution_id" {
  description = "ID de la distribucion CloudFront del frontend."
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_distribution_domain_name" {
  description = "Default domain name de la distribucion (*.cloudfront.net)."
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_distribution_arn" {
  description = "ARN de la distribucion CloudFront del frontend."
  value       = aws_cloudfront_distribution.frontend.arn
}

output "access_logs_bucket_arn" {
  description = "ARN del bucket access-logs de CloudFront."
  value       = aws_s3_bucket.access_logs.arn
}

output "access_logs_bucket_name" {
  description = "Nombre del bucket access-logs de CloudFront."
  value       = aws_s3_bucket.access_logs.id
}
