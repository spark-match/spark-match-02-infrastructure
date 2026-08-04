output "parameter_names" {
  description = "Map con los nombres (paths) de los 8 parametros SSM creados."
  value = {
    eventbridge_bus_arn      = aws_ssm_parameter.eventbridge_bus_arn.name
    db_secret_arn            = aws_ssm_parameter.db_secret_arn.name
    jwt_secret_arn           = aws_ssm_parameter.jwt_secret_arn.name
    db_connection_url        = aws_ssm_parameter.db_connection_url.name
    idempotency_table        = aws_ssm_parameter.idempotency_table.name
    cors_allowed_origins     = aws_ssm_parameter.cors_allowed_origins.name
    private_subnet_ids       = aws_ssm_parameter.private_subnet_ids.name
    lambda_security_group_id = aws_ssm_parameter.lambda_security_group_id.name
  }
}

output "config_prefix" {
  description = "Prefijo comun de los parametros (/spark-match/{env}/config)."
  value       = local.prefix
}
