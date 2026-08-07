variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en nombres de recursos."
  type        = string
  default     = "spark-match"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "project_name debe ser kebab-case lowercase (3-30 chars, solo [a-z0-9-])."
  }
}

variable "environment" {
  description = "Nombre del entorno. Determina nombres de recursos y tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser uno de: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "Region AWS donde corre el servicio. Se inyecta como SPARK_AWS_REGION en el contenedor y se usa en la config de awslogs."
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos del modulo."
  type        = map(string)
  default     = {}
}

###############################################################################
# Red
###############################################################################

variable "vpc_id" {
  description = "ID de la VPC donde corren el ALB y las tasks (output de modules/networking)."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id debe tener formato vpc-<hex> (8-17 chars)."
  }
}

variable "vpc_cidr" {
  description = "CIDR principal de la VPC. Usado para el egress del SG del agente hacia RDS (5432) dentro de la VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr debe ser un CIDR valido (ej. 10.0.0.0/16)."
  }
}

variable "alb_subnet_ids" {
  description = "Subnets donde vive el ALB. Siempre publicas (el ALB es internet-facing) y en >= 2 AZs, requisito de ELB."
  type        = list(string)

  validation {
    condition     = length(var.alb_subnet_ids) >= 2
    error_message = "alb_subnet_ids debe tener al menos 2 subnets en AZs distintas (requisito de Application Load Balancer)."
  }
}

variable "service_subnet_ids" {
  description = "Subnets donde corren las tasks de Fargate. En dev son las publicas (con assign_public_ip=true, evita pagar NAT); en prod son las privadas y el egress sale por el NAT unico."
  type        = list(string)

  validation {
    condition     = length(var.service_subnet_ids) >= 1
    error_message = "service_subnet_ids debe tener al menos 1 subnet."
  }
}

variable "assign_public_ip" {
  description = "Si asignar IP publica a las tasks. true en dev (tasks en subnet publica, sin NAT: es la unica forma de que lleguen a ECR/Bedrock/Secrets); false en prod (subnets privadas + NAT). El SG del agente sigue bloqueando todo ingress que no venga del ALB."
  type        = bool
  default     = false
}

variable "rds_security_group_id" {
  description = "ID del SG de RDS (output de modules/security-groups). El modulo le agrega una rule de ingress 5432 desde el SG del agente, para que la persistencia Postgres (checkpointer/store de LangGraph, schema `agent`) pueda conectarse."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.rds_security_group_id))
    error_message = "rds_security_group_id debe tener formato sg-<hex>."
  }
}

variable "vpc_endpoints_security_group_id" {
  description = "ID del SG de los interface VPC endpoints (output de modules/security-groups). El modulo le agrega una rule de ingress 443 desde el SG del agente. Es obligatoria aunque las tasks tengan IP publica: los endpoints tienen private DNS habilitado, asi que ssm/secretsmanager resuelven a IPs privadas para TODA la VPC y el trafico nunca sale a internet."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.vpc_endpoints_security_group_id))
    error_message = "vpc_endpoints_security_group_id debe tener formato sg-<hex>."
  }
}

variable "enable_cloudfront" {
  description = "Pone una distribucion CloudFront delante del ALB para terminar TLS. Necesario para que el frontend (servido por HTTPS) pueda llamar al agente: el navegador bloquea mixed content y AWS no emite certificados ACM publicos para *.elb.amazonaws.com. Con false, el agente queda accesible solo por HTTP."
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "Price class de la distribucion del agente. PriceClass_100 (US/EU) alcanza y es la mas barata; el trafico esperado es de Peru pero la latencia extra es irrelevante frente al tiempo de inferencia del modelo."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class debe ser PriceClass_100, PriceClass_200 o PriceClass_All."
  }
}

variable "cloudfront_origin_read_timeout" {
  description = "Segundos que CloudFront espera ENTRE bytes del origin antes de cortar. 60 es el maximo sin pedir aumento de quota a AWS. Aplica al hueco entre eventos SSE, no al total del stream: AG-UI emite RUN_STARTED de inmediato y luego tokens, asi que el hueco real es de milisegundos."
  type        = number
  default     = 60

  validation {
    condition     = var.cloudfront_origin_read_timeout >= 1 && var.cloudfront_origin_read_timeout <= 60
    error_message = "cloudfront_origin_read_timeout debe estar entre 1 y 60 (limite de AWS sin aumento de quota)."
  }
}

# Aqui habia `min_protocol_version`. Su descripcion ya avisaba de que
# CloudFront lo ignora mientras se use el certificado por defecto, y aun asi
# se declaraba "para que el dia que llegue el dominio quede en el valor
# correcto sin tocar el modulo". El precio de esa comodidad, medido el
# 2026-08-07, era que cada apply del repo arrastraba un cambio fantasma
# que se aplicaba sin surtir efecto. Se elimina; vuelve el dia que haya
# certificado ACM, junto con `acm_certificate_arn` y `ssl_support_method`.

variable "alb_ingress_cidr_blocks" {
  description = "CIDRs autorizados a alcanzar el ALB en el puerto 80. Default 0.0.0.0/0 porque el agente se consume desde el navegador (frontend en CloudFront) sin IP fija. La autorizacion real la hace el JWT que valida /ag-ui, no la red."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# Contenedor / task
###############################################################################

variable "container_image" {
  description = "Imagen a correr, normalmente `{ecr_repository_url}:bootstrap`. En el primer apply el repositorio ECR esta vacio y las tasks no van a poder arrancar -- es esperado: el pipeline de spark-match-08-deep-agent publica la imagen real y registra una revision nueva de la task definition. Ver `lifecycle.ignore_changes` en aws_ecs_service.this."
  type        = string
}

variable "container_name" {
  description = "Nombre del contenedor dentro de la task definition. Tiene que coincidir con el `container-name` que usa la receta reusable-ecs-deploy.yml de spark-match-01-devops."
  type        = string
  default     = "agent"
}

variable "container_port" {
  description = "Puerto donde escucha el agente. 8080 y no 8000: el frontend reserva localhost:8000 para el backend, por lo que el contenedor del agente no debe colisionar (ver el Dockerfile de spark-match-08-deep-agent)."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "CPU units de la task Fargate (256 = 0.25 vCPU). 512 (0.5 vCPU) por defecto."
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "task_cpu debe ser uno de los valores validos de Fargate: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memoria en MiB de la task Fargate. 1024 (1 GiB) por defecto, combinacion valida con task_cpu=512."
  type        = number
  default     = 1024

  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 30720
    error_message = "task_memory debe estar entre 512 y 30720 MiB."
  }
}

variable "desired_count" {
  description = "Cuantas tasks correr. 1 por defecto: el agente es stateless (el estado de conversacion vive en Postgres, schema `agent`), pero 1 replica alcanza para el trafico inicial y mantiene el costo de Fargate en ~$18/mes."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0 && var.desired_count <= 10
    error_message = "desired_count debe estar entre 0 y 10."
  }
}

variable "agentcore_runtime_role_arn" {
  description = "ARN del role `spark-match-agentcore-runtime-{env}` (output de modules/oidc-github). Es el task role: los permisos que usa el CODIGO del agente en runtime (Bedrock, Secrets Manager, SSM). Su trust policy ya acepta ecs-tasks.amazonaws.com."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z]*:iam::[0-9]{12}:role/", var.agentcore_runtime_role_arn))
    error_message = "agentcore_runtime_role_arn debe ser un ARN valido de IAM role."
  }
}

variable "extra_environment_variables" {
  description = "Env vars adicionales a inyectar en el contenedor, ademas de las que el modulo calcula (SPARK_ENVIRONMENT, SPARK_PERSISTENCE_BACKEND, etc.). Utiles para feature flags sin tener que tocar el modulo."
  type        = map(string)
  default     = {}
}

variable "cors_allowed_origins" {
  description = "Origenes permitidos por el agente, en el formato que espera SPARK_CORS_ORIGINS (JSON array). El caller lo arma con el dominio CloudFront del ambiente."
  type        = string
  default     = "[]"
}

variable "tavily_secret_name" {
  description = "Nombre del secret de Secrets Manager que guarda la API key de Tavily, como string plano. El VALOR se crea fuera de Terraform a proposito (ver el comentario de data.aws_secretsmanager_secret.tavily): aqui solo se resuelve el ARN para inyectarlo como SPARK_TAVILY_API_KEY. En null el agente no recibe la key y web_search cae a DuckDuckGo."
  type        = string
  default     = null
}

variable "max_web_searches_per_session" {
  description = "Limite de busquedas web por sesion (SPARK_MAX_WEB_SEARCHES_PER_SESSION). OJO: 0 NO desactiva la herramienta, desactiva el LIMITE -- src/tools/web_search/handler.py trata cap <= 0 como ilimitado. La descripcion anterior afirmaba lo contrario y dejo a dev con busquedas sin tope."
  type        = number
  default     = 6

  validation {
    condition     = var.max_web_searches_per_session >= 0
    error_message = "max_web_searches_per_session no puede ser negativo (0 = sin limite)."
  }
}

variable "log_level" {
  description = "Nivel de log del agente (SPARK_LOG_LEVEL)."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "log_level debe ser uno de: DEBUG, INFO, WARNING, ERROR."
  }
}

###############################################################################
# Observabilidad
###############################################################################

variable "log_retention_days" {
  description = "Retencion del log group del servicio. 365 en prod (CKV_AWS_338 exige >= 1 anio), 30 en dev."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days debe ser uno de los valores aceptados por CloudWatch Logs."
  }
}

variable "kms_key_arn" {
  description = "ARN de la CMK del proyecto para cifrar el log group del servicio y permitir al execution role descifrar las capas de la imagen ECR. Si null, el log group usa el cifrado default de CloudWatch Logs. Para condicionar recursos a que exista, usa enable_kms_encryption: este valor suele venir de module.kms y no se conoce hasta el apply."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn debe ser null o un ARN valido de KMS."
  }
}

# Existe porque `count` no puede depender de un valor computado.
#
# Los recursos que dan permiso sobre la CMK usaban
# `count = var.kms_key_arn == null ? 0 : 1`. Los callers pasan
# `kms_key_arn = module.kms.kms_key_arn`, que es un atributo de otro modulo,
# asi que terraform no sabe si es null hasta despues del apply y aborta:
#
#     Error: Invalid count argument
#     The "count" value depends on resource attributes that cannot be
#     determined until apply
#
# En `dev` nunca se vio porque la CMK ya existia en el state y el valor si era
# conocido al planificar. Aparecio el 2026-08-07 en el primer `plan-prod` que
# llego a ejecutarse, sobre un ambiente vacio -- el escenario en el que ningun
# atributo se conoce todavia.
#
# Este flag es un booleano plano que sale de tfvars, o sea conocido siempre.
# Va en `false` por defecto para no cambiar el comportamiento de un caller que
# no lo declare y no pase CMK; los dos ambientes de este repo lo ponen en true
# junto al `kms_key_arn`.
variable "enable_kms_encryption" {
  description = "Si crear los permisos del execution role sobre la CMK del proyecto. Debe ir en true exactamente cuando se pasa kms_key_arn. Es un input aparte, y no una comprobacion sobre kms_key_arn, porque ese valor viene de otro modulo y no se conoce en tiempo de plan."
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Si activar CloudWatch Container Insights en el cluster. false por defecto: cuesta por metrica ingerida y el presupuesto de la cuenta es $200/mes; los logs de la aplicacion ya van a CloudWatch Logs y el circuit breaker cubre el rollback automatico."
  type        = bool
  default     = false
}

###############################################################################
# ALB
###############################################################################

variable "alb_idle_timeout" {
  description = "Idle timeout del ALB en segundos. 300 (no el default de 60) porque /ag-ui responde con SSE: un stream largo sin bytes intermedios se cortaria a los 60s."
  type        = number
  default     = 300

  validation {
    condition     = var.alb_idle_timeout >= 60 && var.alb_idle_timeout <= 4000
    error_message = "alb_idle_timeout debe estar entre 60 y 4000 segundos."
  }
}

variable "enable_deletion_protection" {
  description = "Si proteger el ALB contra borrado. true en prod, false en dev (permite `terraform destroy` mientras se itera)."
  type        = bool
  default     = false
}

variable "blocked_path_patterns" {
  description = "Paths que el listener responde con 404 fijo sin llegar al contenedor. FastAPI expone /docs, /redoc y /openapi.json y hoy el agente no los desactiva por codigo (queda como PR-DA1); bloquearlos en el ALB evita publicar el esquema completo de la API mientras tanto."
  type        = list(string)
  default     = ["/docs", "/docs/*", "/redoc", "/redoc/*", "/openapi.json"]
}

variable "health_check_path" {
  description = "Path del health check del target group. /health devuelve 200 con {status, agent, environment} (src/api/app.py del deep-agent)."
  type        = string
  default     = "/health"
}

variable "health_check_grace_period_seconds" {
  description = "Segundos que ECS ignora el health check del ALB tras arrancar una task. Cubre el arranque de uvicorn + la conexion inicial a Postgres (setup del checkpointer)."
  type        = number
  default     = 60
}

###############################################################################
# Contrato SSM (ADR 0002)
###############################################################################

variable "ecr_repository_url" {
  description = "URL del repositorio ECR (output de modules/ecr). Se publica en SSM para que el pipeline del deep-agent no tenga que hardcodearla."
  type        = string
}

variable "db_secret_ssm_param" {
  description = "Path del parametro SSM que contiene el ARN del secret de credenciales de RDS. El agente lo resuelve en arranque para construir el DSN de Postgres (schema `agent`)."
  type        = string
  default     = null
}

variable "jwt_secret_ssm_param" {
  description = "Path del parametro SSM que contiene el ARN del secret JWT. El agente lo usa para validar los tokens que emite el backend."
  type        = string
  default     = null
}
