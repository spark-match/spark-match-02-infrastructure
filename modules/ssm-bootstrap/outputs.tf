output "parameter_names" {
  description = "Map con los nombres (paths) de los 11 parametros SSM creados."
  value = {
    reports_bucket                   = aws_ssm_parameter.reports_bucket.name
    reports_max_per_user_per_day     = aws_ssm_parameter.reports_max_per_user_per_day.name
    reports_min_profile_completeness = aws_ssm_parameter.reports_min_profile_completeness.name
    eventbridge_bus_arn              = aws_ssm_parameter.eventbridge_bus_arn.name
    db_secret_arn                    = aws_ssm_parameter.db_secret_arn.name
    jwt_secret_arn                   = aws_ssm_parameter.jwt_secret_arn.name
    db_connection_url                = aws_ssm_parameter.db_connection_url.name
    idempotency_table                = aws_ssm_parameter.idempotency_table.name
    cors_allowed_origins             = aws_ssm_parameter.cors_allowed_origins.name
    private_subnet_ids               = aws_ssm_parameter.private_subnet_ids.name
    lambda_security_group_id         = aws_ssm_parameter.lambda_security_group_id.name
  }
}

output "config_prefix" {
  description = "Prefijo comun de los parametros (/spark-match/{env}/config)."
  value       = local.prefix
}
