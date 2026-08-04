output "parameter_names" {
  description = "Map con los nombres (paths) de los 6 parametros SSM creados."
  value = {
    eventbridge_bus_arn  = aws_ssm_parameter.eventbridge_bus_arn.name
    db_secret_arn        = aws_ssm_parameter.db_secret_arn.name
    jwt_secret_arn       = aws_ssm_parameter.jwt_secret_arn.name
    db_connection_url    = aws_ssm_parameter.db_connection_url.name
    idempotency_table    = aws_ssm_parameter.idempotency_table.name
    cors_allowed_origins = aws_ssm_parameter.cors_allowed_origins.name
  }
}

output "config_prefix" {
  description = "Prefijo comun de los parametros (/spark-match/{env}/config)."
  value       = local.prefix
}
