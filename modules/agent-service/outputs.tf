output "cluster_name" {
  description = "Nombre del cluster ECS. La receta reusable-ecs-deploy.yml lo recibe como `cluster-name`."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ARN del cluster ECS."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "Nombre del servicio ECS. La receta reusable-ecs-deploy.yml lo recibe como `service-name`."
  value       = aws_ecs_service.this.name
}

output "task_definition_family" {
  description = "Family de la task definition. El pipeline registra revisiones nuevas sobre esta misma family."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "ARN de la revision bootstrap de la task definition. Solo informativo: a partir del primer deploy el pipeline es el owner de la revision activa (ver lifecycle.ignore_changes del servicio)."
  value       = aws_ecs_task_definition.this.arn
}

output "container_name" {
  description = "Nombre del contenedor dentro de la task definition. La receta reusable-ecs-deploy.yml lo recibe como `container-name`."
  value       = var.container_name
}

output "execution_role_arn" {
  description = "ARN del execution role de la task (`spark-match-agentcore-exec-{env}`), referenciado por los statements IAMPassRoleToAgentCore e IAMManageAgentCoreExecRole de la policy de deploy del agente."
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "Nombre del execution role de la task."
  value       = aws_iam_role.execution.name
}

output "alb_arn" {
  description = "ARN del Application Load Balancer del agente."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS publico del ALB. Tambien se publica en SSM como agent-endpoint-url."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID del ALB, necesario si en algun momento se le pone un alias Route53."
  value       = aws_lb.this.zone_id
}

output "agent_endpoint_url" {
  description = "URL base del agente (`http://{alb-dns}`), el mismo valor que queda en /{project}/{env}/config/agent-endpoint-url."
  value       = "http://${aws_lb.this.dns_name}"
}

output "target_group_arn" {
  description = "ARN del target group del agente."
  value       = aws_lb_target_group.this.arn
}

output "sg_agent_id" {
  description = "ID del SG de las tasks del agente."
  value       = aws_security_group.agent.id
}

output "sg_agent_alb_id" {
  description = "ID del SG del ALB del agente."
  value       = aws_security_group.alb.id
}

output "log_group_name" {
  description = "Nombre del log group donde el contenedor escribe stdout/stderr."
  value       = aws_cloudwatch_log_group.service.name
}

output "ssm_parameter_names" {
  description = "Parametros SSM publicados por este modulo (extension del contrato ADR 0002)."
  value = [
    aws_ssm_parameter.agent_endpoint_url.name,
    aws_ssm_parameter.agent_ecr_repository_url.name,
  ]
}
