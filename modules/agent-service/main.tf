###############################################################################
# Module: agent-service
#
# Plano de computo de spark-match-08-deep-agent: cluster ECS + task definition
# Fargate ARM64 + servicio detras de un Application Load Balancer publico.
#
# Por que ECS Fargate y no Bedrock AgentCore Runtime: el agente necesita
# persistencia real en Postgres (checkpointer/store de LangGraph sobre el
# schema `agent`), conexion por TCP 5432 a la instancia RDS de la VPC, y
# streaming SSE de larga duracion en /ag-ui. Fargate cubre las tres cosas con
# un modelo de costo predecible (~$18/mes con 0.5 vCPU / 1 GiB).
#
# Por que ALB y no API Gateway HTTP API: /ag-ui responde con Server-Sent
# Events y el timeout de integracion de HTTP API (30s, no configurable)
# cortaria los streams. El ALB permite idle_timeout de hasta 4000s
# (var.alb_idle_timeout, 300 por defecto).
#
# ARM64 no es negociable: ambas etapas del Dockerfile de spark-match-08-deep-agent
# declaran `--platform=linux/arm64`. Una task definition X86_64 fallaria al
# arrancar con "exec format error".
#
# Bootstrap: en el primer apply el repositorio ECR esta vacio, por lo que las
# tasks no van a poder arrancar hasta que el pipeline del deep-agent publique
# la imagen. Es esperado y no rompe el apply (el servicio no espera steady
# state). A partir de ahi el pipeline registra revisiones nuevas de la task
# definition y este modulo deja de ser el owner de ese campo -- ver
# `lifecycle.ignore_changes` en aws_ecs_service.this.
#
# Ownership de red:
#   - Los 2 SGs (ALB y agente) los crea este modulo, no modules/security-groups,
#     porque solo tienen sentido con este servicio.
#   - La rule de ingress 5432 sobre el SG de RDS tambien la crea este modulo,
#     apuntando a un SG que es propiedad de modules/security-groups. Es el
#     mismo patron "terraform-orphan" que ya usa ese modulo: el SG de RDS
#     declara `lifecycle.ignore_changes = [ingress, egress]` justamente para
#     que rules externas puedan adjuntarse sin drift fantasma.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "agent-service"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  name_prefix    = "${var.project_name}-agent-${var.environment}"
  cluster_name   = "${var.project_name}-${var.environment}"
  log_group_name = "/aws/${var.project_name}/agent/${var.environment}/service"
  ssm_prefix     = "/${var.project_name}/${var.environment}/config"

  # Los defaults apuntan al contrato SSM de ADR 0002 para el mismo environment.
  # Se dejan como variables para poder apuntar a otro ambiente en pruebas.
  db_secret_ssm_param  = coalesce(var.db_secret_ssm_param, "${local.ssm_prefix}/db-secret-arn")
  jwt_secret_ssm_param = coalesce(var.jwt_secret_ssm_param, "${local.ssm_prefix}/jwt-secret-arn")

  base_environment_variables = {
    SPARK_ENVIRONMENT                  = var.environment
    SPARK_AWS_REGION                   = var.aws_region
    SPARK_PERSISTENCE_BACKEND          = "postgres"
    SPARK_DB_SECRET_SSM_PARAM          = local.db_secret_ssm_param
    SPARK_JWT_SECRET_SSM_PARAM         = local.jwt_secret_ssm_param
    SPARK_CORS_ORIGINS                 = var.cors_allowed_origins
    SPARK_MAX_WEB_SEARCHES_PER_SESSION = tostring(var.max_web_searches_per_session)
    SPARK_LOG_LEVEL                    = var.log_level
    SPARK_API_PORT                     = tostring(var.container_port)
    SPARK_API_HOST                     = "0.0.0.0"
  }

  environment_variables = merge(local.base_environment_variables, var.extra_environment_variables)

  # `secrets` en vez de `environment`: el agente de ECS resuelve el valor al
  # arrancar la task y lo inyecta como env var en el contenedor. Asi la key
  # no aparece en `describe-task-definition`, que es lectura publica para
  # cualquiera con acceso al cluster.
  container_secrets = var.tavily_secret_name == null ? [] : [
    {
      name      = "SPARK_TAVILY_API_KEY"
      valueFrom = data.aws_secretsmanager_secret.tavily[0].arn
    }
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# El VALOR de la API key se crea fuera de Terraform (consola o
# `aws secretsmanager create-secret`) y aqui solo se lee el ARN.
#
# No es pereza: un `aws_secretsmanager_secret_version` guardaria la key EN
# CLARO dentro del tfstate, y el tfstate vive en S3 -- cualquiera con acceso
# al bucket la leeria, y quedaria ademas en cada version del objeto. Es el
# mismo agujero que ya tiene modules/secrets-bootstrap con el JWT, salvo que
# ese valor lo genera Terraform y este lo emite un tercero.
#
# Un data source falla el plan si el secret no existe, de ahi el count: con
# tavily_secret_name = null el ambiente se levanta sin Tavily y web_search
# cae a DuckDuckGo.
data "aws_secretsmanager_secret" "tavily" {
  count = var.tavily_secret_name == null ? 0 : 1

  name = var.tavily_secret_name
}

###############################################################################
# Security groups
###############################################################################
# Dos SGs con `egress = []` inline para neutralizar el default
# "egress allow all 0.0.0.0/0" de AWS, y las rules en recursos
# `aws_security_group_rule` separados (mismo patron que modules/security-groups,
# ver IMPROVEMENTS.md [A6] [SEC-08] [B12]).
###############################################################################

resource "aws_security_group" "alb" {
  # checkov:skip=CKV2_AWS_5:rules adjuntas via aws_security_group_rule mas abajo (patron terraform-orphan; ingress/egress=[] bloquea la default rule de AWS).
  name        = "${var.project_name}-sg-agent-alb-${var.environment}"
  description = "Security group for the deep-agent Application Load Balancer in ${var.environment}"
  vpc_id      = var.vpc_id

  egress = []

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-agent-alb-${var.environment}"
  })

  lifecycle {
    ignore_changes = [description, ingress, egress]
  }
}

resource "aws_security_group_rule" "alb_ingress_http" {
  # checkov:skip=CKV_AWS_260:el ALB es internet-facing a proposito -- el agente se consume desde el navegador (frontend en CloudFront) sin IP de origen fija. La autorizacion la hace el JWT que valida /ag-ui, no la red. Restringible via var.alb_ingress_cidr_blocks.
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.alb_ingress_cidr_blocks
  description       = "Allow inbound HTTP to the public agent ALB"
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_to_agent" {
  type                     = "egress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.agent.id
  description              = "Allow the ALB to reach the agent tasks only"
  security_group_id        = aws_security_group.alb.id
}

resource "aws_security_group" "agent" {
  # checkov:skip=CKV2_AWS_5:rules adjuntas via aws_security_group_rule mas abajo (patron terraform-orphan; ingress/egress=[] bloquea la default rule de AWS).
  name        = "${var.project_name}-sg-agent-${var.environment}"
  description = "Security group for the deep-agent Fargate tasks in ${var.environment}"
  vpc_id      = var.vpc_id

  egress = []

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg-agent-${var.environment}"
  })

  lifecycle {
    ignore_changes = [description, ingress, egress]
  }
}

resource "aws_security_group_rule" "agent_ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow traffic to the agent container only from the ALB"
  security_group_id        = aws_security_group.agent.id
}

resource "aws_security_group_rule" "agent_egress_https" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS egress (ECR image pull, Bedrock, Secrets Manager, SSM, CloudWatch)"
  security_group_id = aws_security_group.agent.id
}

resource "aws_security_group_rule" "agent_egress_postgres" {
  type              = "egress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  description       = "Allow Postgres egress to the RDS instance inside the VPC"
  security_group_id = aws_security_group.agent.id
}

# Contraparte en el SG de RDS (propiedad de modules/security-groups). Ver la
# nota de "Ownership de red" en el encabezado del modulo.
resource "aws_security_group_rule" "rds_ingress_from_agent" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.agent.id
  description              = "Allow Postgres traffic from the deep-agent Fargate tasks"
  security_group_id        = var.rds_security_group_id
}

# Contraparte en el SG de los interface VPC endpoints. Sin esto el arranque del
# agente se CUELGA (no falla) en build_persistence(): lee
# /spark-match/dev/config/db-secret-arn de SSM y despues el secret de Secrets
# Manager, y esas dos llamadas nunca vuelven.
#
# El egress 443 del agente no alcanza: los endpoints tienen private_dns_enabled,
# asi que ssm/secretsmanager/events resuelven a las IPs privadas del endpoint
# para TODA la VPC -- tambien para una task con IP publica. El trafico va al
# endpoint, el SG lo descarta sin RST, y el cliente queda esperando hasta el
# timeout (que en el arranque no existe). De ahi el sintoma exacto: el log se
# queda en "Waiting for application startup." y el health check nunca pasa.
#
# La descripcion de la rule equivalente en modules/security-groups dice
# "from Lambdas only": esta es la que agrega al agente.
resource "aws_security_group_rule" "endpoints_ingress_from_agent" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.agent.id
  description              = "Allow HTTPS to VPC endpoints from the deep-agent Fargate tasks"
  security_group_id        = var.vpc_endpoints_security_group_id
}

###############################################################################
# Application Load Balancer
###############################################################################

resource "aws_lb" "this" {
  # checkov:skip=CKV_AWS_91:access logs del ALB requieren un bucket S3 dedicado con bucket policy para la cuenta de ELB; queda como follow-up explicito del plan de despliegue. La visibilidad de request va hoy por los logs del contenedor en CloudWatch.
  # checkov:skip=CKV_AWS_150:deletion protection es dependiente del ambiente (var.enable_deletion_protection); live/prod la activa, dev la deja en false para poder iterar con terraform destroy.
  # checkov:skip=CKV2_AWS_20:el redirect HTTP->HTTPS presupone un listener HTTPS, que no existe en v1 (sin dominio ni certificado ACM para el agente). Mismo follow-up que CKV_AWS_2.
  # checkov:skip=CKV2_AWS_28:sin WAF en v1 por costo (~$5/mes de web ACL + cargo por millon de requests) sobre un budget de cuenta de $200/mes. Mitigacion actual: /ag-ui exige JWT valido emitido por el backend y los paths de documentacion de FastAPI estan cortados en el listener. Poner el agente detras de CloudFront + WAF es el mismo follow-up que la terminacion TLS.
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.alb_subnet_ids

  # 300s (no el default de 60) porque /ag-ui responde con SSE y un stream sin
  # bytes intermedios se cortaria antes de terminar.
  idle_timeout = var.alb_idle_timeout

  enable_deletion_protection = var.enable_deletion_protection

  # Descarta headers HTTP malformados antes de reenviarlos al contenedor
  # (defensa contra request smuggling). Ref: CKV_AWS_131.
  drop_invalid_header_fields = true

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

resource "aws_lb_target_group" "this" {
  # checkov:skip=CKV_AWS_378:el hop ALB -> contenedor es HTTP dentro de la VPC, sobre un SG que solo acepta trafico del ALB. TLS end-to-end depende de poner el agente detras de CloudFront, follow-up explicito del plan.
  name        = "${var.project_name}-agent-tg-${var.environment}"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  # 30s en vez de los 300 por default: acelera los rollouts sin cortar
  # requests en vuelo (el agente responde en segundos, no en minutos).
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-agent-tg-${var.environment}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  # checkov:skip=CKV_AWS_2:HTTP puro es deliberado en v1 -- no hay dominio ni certificado ACM para el agente todavia. Poner el agente detras de CloudFront (que ya termina TLS para el frontend) es follow-up explicito del plan de despliegue.
  # checkov:skip=CKV_AWS_103:sin listener HTTPS no hay ssl_policy que fijar; se resuelve junto con CKV_AWS_2.
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.common_tags
}

# FastAPI publica /docs, /redoc y /openapi.json por default y el agente todavia
# no los desactiva por codigo (queda como PR-DA1). Cortarlos en el ALB evita
# exponer el esquema completo de la API mientras tanto.
resource "aws_lb_listener_rule" "block_api_docs" {
  count = length(var.blocked_path_patterns) > 0 ? 1 : 0

  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ detail = "Not Found" })
      status_code  = "404"
    }
  }

  condition {
    path_pattern {
      values = var.blocked_path_patterns
    }
  }

  tags = local.common_tags
}

###############################################################################
# IAM - execution role
###############################################################################
# Dos roles distintos, como exige la separacion de responsabilidades de ECS:
#   - execution role (este): lo usa el AGENTE DE ECS para arrancar la task
#     (pull de la imagen desde ECR, escribir el log stream). Nunca lo ve el
#     codigo de la aplicacion.
#   - task role (var.agentcore_runtime_role_arn, creado en modules/oidc-github):
#     lo usa el CODIGO en runtime (Bedrock, Secrets Manager, SSM).
#
# El nombre `spark-match-agentcore-exec-{env}` no es libre: las policies
# spark-match-bedrock-agentcore-deploy.json ya lo referencian en los statements
# IAMPassRoleToAgentCore e IAMManageAgentCoreExecRole.
#
# El acceso a la CMK va por policy de identidad (no por var.user_role_arns de
# modules/kms) a proposito: agregar este role a la key policy crearia un ciclo
# kms -> agent-service -> kms. Funciona porque la key policy de la CMK ya tiene
# el statement RootAccountManage, que habilita la delegacion via IAM.
###############################################################################

data "aws_iam_policy_document" "execution_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.${data.aws_partition.current.dns_suffix}"]
    }

    # Evita el confused deputy problem: solo tasks de ESTA cuenta pueden
    # asumir el role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-agentcore-exec-${var.environment}"
  description        = "ECS task execution role for the deep-agent service in ${var.environment} (image pull + log streaming)"
  assume_role_policy = data.aws_iam_policy_document.execution_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-agentcore-exec-${var.environment}"
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Descifrado de la CMK: necesario para bajar las capas de la imagen si el
# repositorio ECR esta cifrado con KMS, y para escribir en el log group
# cifrado con la misma key.
#
# El count va sobre `enable_kms_encryption` y NO sobre `kms_key_arn == null`.
# Ese ARN viene de module.kms, o sea que es un atributo computado, y terraform
# no puede resolver un count que dependa de algo que no conoce hasta el apply.
# Ver la nota junto a la variable en variables.tf.
data "aws_iam_policy_document" "execution_kms" {
  count = var.enable_kms_encryption ? 1 : 0

  statement {
    sid    = "DecryptProjectCMK"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "execution_kms" {
  count = var.enable_kms_encryption ? 1 : 0

  name   = "${var.project_name}-agentcore-exec-kms-${var.environment}"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_kms[0].json
}

# Va en el EXECUTION role, no en el task role: quien resuelve el bloque
# `secrets` es el agente de ECS durante el arranque de la task, antes de que
# exista proceso de Python. Con el permiso en el task role la task muere en
# PROVISIONING con ResourceInitializationError.
#
# AmazonECSTaskExecutionRolePolicy (adjunta arriba) NO trae
# secretsmanager:GetSecretValue; solo cubre pull de ECR y logs.
#
# Sin statement de KMS a proposito: si el secret usa la key gestionada por AWS
# (`aws/secretsmanager`, el default al crearlo), su key policy ya permite el
# descifrado a quien tenga GetSecretValue. Y si se crea con la CMK del
# proyecto, execution_kms de arriba ya da kms:Decrypt sobre ella.
data "aws_iam_policy_document" "execution_secrets" {
  count = var.tavily_secret_name == null ? 0 : 1

  statement {
    sid       = "ReadTavilyApiKey"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.tavily[0].arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = var.tavily_secret_name == null ? 0 : 1

  name   = "${var.project_name}-agentcore-exec-secrets-${var.environment}"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

###############################################################################
# Observabilidad
###############################################################################

resource "aws_cloudwatch_log_group" "service" {
  # checkov:skip=CKV_AWS_338:la retencion es dependiente del ambiente (var.log_retention_days); live/prod usa 365 dias para cumplir el minimo de 1 anio, dev usa 30 para no pagar retencion de logs desechables.
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.common_tags, {
    Name = local.log_group_name
  })
}

###############################################################################
# ECS - cluster, task definition y servicio
###############################################################################

resource "aws_ecs_cluster" "this" {
  # checkov:skip=CKV_AWS_65:Container Insights se cobra por metrica ingerida y el presupuesto de la cuenta es $200/mes. Los logs de la aplicacion ya van a CloudWatch Logs y el deployment circuit breaker cubre el rollback automatico. Activable via var.enable_container_insights.
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
}

resource "aws_ecs_task_definition" "this" {
  # checkov:skip=CKV_AWS_336:readonlyRootFilesystem=true rompe el runtime de Python (escrituras a /tmp de httpx, uvicorn y el checkpointer de LangGraph). Mitigado por usuario no-root (spark:1001, ver el Dockerfile del deep-agent) y por un filesystem efimero que muere con la task.
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = var.agentcore_runtime_role_arn

  # ARM64 obligatorio: el Dockerfile del deep-agent construye ambas etapas con
  # `--platform=linux/arm64`. Con X86_64 la task arranca y muere con
  # "exec format error".
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for key in sort(keys(local.environment_variables)) : {
          name  = key
          value = local.environment_variables[key]
        }
      ]

      secrets = local.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = var.container_name
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:${var.container_port}${var.health_check_path}').status==200 else 1)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}

resource "aws_ecs_service" "this" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Ignora el health check del ALB durante el arranque de uvicorn + el setup
  # del checkpointer contra Postgres.
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.service_subnet_ids
    security_groups  = [aws_security_group.agent.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # Si el deployment nuevo no logra estabilizarse, ECS revierte solo a la
  # revision anterior en vez de dejar el servicio caido.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })

  # A partir del primer deploy real, el owner de `task_definition` es el
  # pipeline de spark-match-08-deep-agent (receta reusable-ecs-deploy.yml de
  # spark-match-01-devops), que registra una revision nueva por cada imagen.
  # Sin este ignore_changes, cada `terraform apply` haria rollback del
  # servicio a la revision bootstrap. `desired_count` se ignora por la misma
  # razon si en algun momento se agrega autoscaling.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

###############################################################################
# Contrato SSM (ADR 0002)
###############################################################################
# Dos parametros nuevos bajo /{project}/{env}/config/ para que ni el frontend
# ni el pipeline del deep-agent tengan que hardcodear endpoints ni URLs de
# registry.
###############################################################################

resource "aws_ssm_parameter" "agent_endpoint_url" {
  # checkov:skip=CKV_AWS_337:valor es una URL publica (DNS del ALB o de CloudFront), no un secreto.
  # checkov:skip=CKV2_AWS_34:mismo razonamiento que CKV_AWS_337 -- una URL publica no necesita SecureString/KMS.
  name  = "${local.ssm_prefix}/agent-endpoint-url"
  type  = "String"
  value = local.agent_public_url
  tags  = local.common_tags
}

###############################################################################
# CloudFront delante del ALB -- terminacion TLS sin dominio propio
###############################################################################
# Por que hace falta: el frontend se sirve por HTTPS desde CloudFront. Una
# pagina HTTPS no puede abrir un fetch/EventSource contra `http://`: el
# navegador lo bloquea por mixed content, sin excepcion posible desde la app.
# Y no se puede resolver poniendole un ACM al ALB, porque AWS no emite
# certificados publicos para *.elb.amazonaws.com -- haria falta dominio propio.
#
# CloudFront resuelve las dos cosas a la vez: da HTTPS gratis sobre
# *.cloudfront.net y es donde se enganchara el dominio real cuando exista, asi
# que no es trabajo desechable.
#
# Configuracion critica para SSE (/ag-ui responde text/event-stream):
#
#   compress = false        -- comprimir obliga a CloudFront a BUFFERAR la
#                              respuesta, y un stream bufferado deja de ser un
#                              stream: el usuario no ve nada hasta el final.
#   cache_policy_id         -- CachingDisabled (managed). Cachear un stream de
#                              chat no tiene sentido y romperia el aislamiento
#                              entre usuarios.
#   origin_request_policy   -- AllViewer (managed). Reenvia el header
#                              Authorization; sin el, /ag-ui responde 401.
#   allowed_methods         -- /ag-ui es POST, no GET.
#   origin_read_timeout     -- 60s (maximo sin subir quota). Aplica ENTRE bytes,
#                              no al total: AG-UI emite RUN_STARTED de
#                              inmediato y luego tokens, asi que el hueco real
#                              entre eventos es de milisegundos.
###############################################################################

locals {
  agent_public_url = (
    var.enable_cloudfront
    ? "https://${aws_cloudfront_distribution.agent[0].domain_name}"
    : "http://${aws_lb.this.dns_name}"
  )
}

resource "aws_cloudfront_distribution" "agent" {
  # checkov:skip=CKV_AWS_68:WAF fuera de scope en v1 (mismo razonamiento que el ALB). La autorizacion la hace el JWT que valida /ag-ui.
  # checkov:skip=CKV_AWS_310:origin failover requiere 2 origins; el agente tiene uno solo.
  # checkov:skip=CKV_AWS_374:geo restriction deshabilitada (mismo criterio que el frontend).
  # checkov:skip=CKV2_AWS_32:response headers policy no configurada en v1; el agente ya emite sus propios security headers via SecurityHeadersMiddleware.
  # checkov:skip=CKV2_AWS_42:sin dominio custom todavia -- se usa el certificado default de CloudFront. Ese ES el objetivo de este recurso.
  # checkov:skip=CKV2_AWS_47:WAFv2 con regla Log4j -- depende de WAF (mismo defer que CKV_AWS_68).
  # checkov:skip=CKV_AWS_305:sin default_root_object a proposito. Esta distribucion no sirve un sitio estatico: su unico origin es el ALB del agente y todo lo que expone son rutas de API (/ag-ui, /health, /sessions). No hay index.html que servir en la raiz, asi que la regla no aplica. El frontend, que si es estatico, es otra distribucion y otro modulo.
  # checkov:skip=CKV_AWS_86:access logging de CloudFront requiere bucket dedicado; follow-up junto con el del ALB (CKV_AWS_91).
  count = var.enable_cloudfront ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "Spark Match deep-agent (${var.environment}) -- terminacion TLS sobre el ALB"
  price_class     = var.cloudfront_price_class
  http_version    = "http2and3"

  origin {
    domain_name = aws_lb.this.dns_name
    origin_id   = "alb-${local.name_prefix}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # Ver la nota de SSE arriba.
      origin_read_timeout      = var.cloudfront_origin_read_timeout
      origin_keepalive_timeout = 60
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb-${local.name_prefix}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    # NO comprimir: rompe el streaming. Ver la nota de arriba.
    compress = false

    # Managed-CachingDisabled
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # Managed-AllViewer (reenvia Authorization, query strings y cookies)
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.min_protocol_version
  }

  tags = local.common_tags
}

resource "aws_ssm_parameter" "agent_ecr_repository_url" {
  # checkov:skip=CKV_AWS_337:valor es la URL de un repositorio ECR, no un secreto.
  # checkov:skip=CKV2_AWS_34:mismo razonamiento que CKV_AWS_337 -- una URL de registry no necesita SecureString/KMS.
  name  = "${local.ssm_prefix}/agent-ecr-repository-url"
  type  = "String"
  value = var.ecr_repository_url
  tags  = local.common_tags
}
