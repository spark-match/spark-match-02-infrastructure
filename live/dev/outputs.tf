###############################################################################
# Outputs del entorno dev
###############################################################################
#
# Placeholder: en Fase 1 este archivo empezara a exportar IDs de los recursos
# creados por modules/* (VPC, security groups, KMS keys, SSM parameter ARNs).
#
# Convenciones para los nombres de outputs:
#   - *_id      -> identificador del recurso (vpc-xxx, sg-xxx)
#   - *_arn     -> ARN completo
#   - *_endpoint -> URL o endpoint de servicio
#   - *_<env>_<recurso>   -> nombres con scope explicito
#
# Los outputs que cruzan repos (03-backend, 08-deep-agent) deben exportarse
# via `export { name = ... }` para que SSM parameter store los pueda consumir
# desde otros tools (SAM, AgentCore CLI) con `data "aws_ssm_parameter"`.
