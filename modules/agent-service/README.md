# Module: `agent-service`

Plano de cómputo de `spark-match-08-deep-agent`: cluster ECS + task definition Fargate **ARM64** + servicio detrás de un Application Load Balancer público.

## Decisiones

| Decisión | Por qué |
|---|---|
| **ECS Fargate**, no Bedrock AgentCore Runtime | El agente necesita persistencia real en Postgres (checkpointer/store de LangGraph sobre el schema `agent`), conexión TCP 5432 a la RDS de la VPC, y streaming SSE de larga duración. Fargate cubre las tres con costo predecible (~$18/mes a 0.5 vCPU / 1 GiB). |
| **ALB**, no API Gateway HTTP API | `/ag-ui` responde con Server-Sent Events y el timeout de integración de HTTP API (30 s, no configurable) cortaría los streams. El ALB permite `idle_timeout` de hasta 4000 s (300 por defecto). |
| **ARM64** | Ambas etapas del `Dockerfile` del deep-agent declaran `--platform=linux/arm64`. Una task definition `X86_64` arranca y muere con `exec format error`. |
| **Puerto 8080** | El frontend reserva `localhost:8000` para el backend; el contenedor del agente no debe colisionar. |
| **Execution role separado del task role** | El *execution role* (`spark-match-agentcore-exec-{env}`, creado acá) lo usa el agente de ECS para el pull de la imagen y el log stream. El *task role* (`spark-match-agentcore-runtime-{env}`, de `modules/oidc-github`) lo usa el código en runtime (Bedrock, Secrets Manager, SSM). |

## Bootstrap

En el primer `apply` el repositorio ECR está vacío, así que las tasks **no van a poder arrancar** hasta que el pipeline del deep-agent publique la imagen. Es esperado y no rompe el apply (el servicio no espera *steady state*).

A partir de ahí el pipeline registra revisiones nuevas de la task definition y este módulo deja de ser el owner de ese campo:

```hcl
lifecycle {
  ignore_changes = [task_definition, desired_count]
}
```

Sin ese `ignore_changes`, cada `terraform apply` haría rollback del servicio a la revisión bootstrap.

## Ownership de red

- Los 2 SGs (ALB y agente) los crea este módulo, no `modules/security-groups`, porque solo tienen sentido con este servicio.
- La rule de ingress 5432 sobre el SG de **RDS** también la crea este módulo, apuntando a un SG que es propiedad de `modules/security-groups`. Es el mismo patrón *terraform-orphan* que ya usa ese módulo: el SG de RDS declara `lifecycle.ignore_changes = [ingress, egress]` justamente para que rules externas puedan adjuntarse sin drift fantasma.

## dev vs prod

| | dev | prod |
|---|---|---|
| Subnets de las tasks | públicas, `assign_public_ip = true` | privadas, `assign_public_ip = false` |
| Por qué | dev no tiene NAT (`enable_nat_gateway = false`); es la única forma de llegar a ECR/Bedrock/Secrets sin sumar ~$36.50/mes | el egress sale por el NAT único del checkpoint de costos |
| `log_retention_days` | 30 | 365 (`CKV_AWS_338`) |
| `enable_deletion_protection` | `false` | `true` |

En ambos casos el SG del agente rechaza todo ingress que no venga del SG del ALB, así que la IP pública de dev no expone el contenedor.

## Contrato con el pipeline

Los outputs alimentan directamente los inputs de `reusable-ecs-deploy.yml` (`spark-match-01-devops`):

| Output | Input de la receta |
|---|---|
| `cluster_name` | `cluster-name` |
| `service_name` | `service-name` |
| `container_name` | `container-name` |

Y el módulo publica dos parámetros SSM nuevos, extensión del contrato de ADR 0002:

- `/{project}/{env}/config/agent-endpoint-url` → `http://{alb-dns}`
- `/{project}/{env}/config/agent-ecr-repository-url`

## Hallazgos suprimidos

Todos comparten **una sola causa raíz**: el agente todavía no está detrás de CloudFront. Hoy no existe dominio propio ni certificado ACM para él, así que el ALB solo puede terminar HTTP y no hay bucket de access logs aprovisionado. Ponerlo detrás de CloudFront (que ya termina TLS para el frontend) resuelve TLS y access logs de una vez, y está anotado como follow-up explícito del plan de despliegue.

| Herramienta | Regla | Qué dice |
|---|---|---|
| checkov | `CKV_AWS_2`, `CKV_AWS_103`, `CKV2_AWS_20` | listener HTTP sin redirect a HTTPS |
| checkov | `CKV_AWS_91` | ALB sin access logs |
| checkov | `CKV2_AWS_28` | ALB público sin WAF |
| Sonar | `terraform:S5332` | clear-text traffic |
| Sonar | `terraform:S6258` | `access_logs` omitido |

`CKV2_AWS_28` (WAF) es la excepción: se omite por costo (~$5/mes de web ACL + cargo por millón de requests) sobre un budget de cuenta de $200/mes, no por falta de dominio.

Los `checkov:skip` viven en el propio recurso; las supresiones de Sonar viven en `sonar-project.properties` en la raíz del repo, apuntadas a regla + archivo concretos. **Cuando el agente quede detrás de CloudFront, ambas se borran.**

Mitigaciones vigentes mientras tanto:

- `/ag-ui` exige un JWT válido emitido por el backend — la autorización la hace el token, no la red.
- El listener corta `/docs`, `/redoc` y `/openapi.json` con un 404 fijo.
- El SG de las tasks solo acepta tráfico del SG del ALB.
- Los logs de aplicación van al log group `/aws/spark-match/agent/{env}/service`.

## Wiring esperado

```hcl
module "agent_service" {
  source = "../../modules/agent-service"

  project_name = "spark-match"
  environment  = "prod"
  aws_region   = "us-east-1"

  vpc_id   = module.networking.vpc_id
  vpc_cidr = var.vpc_cidr

  alb_subnet_ids     = module.networking.public_subnet_ids   # >= 2 AZs (requisito de ELB)
  service_subnet_ids = module.networking.private_subnet_ids
  assign_public_ip   = false

  rds_security_group_id      = module.security_groups.sg_rds_id
  agentcore_runtime_role_arn = module.oidc_github.agentcore_runtime_role_arn

  container_image    = "${module.ecr.repository_url}:bootstrap"
  ecr_repository_url = module.ecr.repository_url

  cors_allowed_origins = jsonencode([
    "https://${module.frontend_hosting.frontend_distribution_domain_name}",
  ])

  log_retention_days         = 365
  kms_key_arn                = module.kms.kms_key_arn
  enable_deletion_protection = true
}
```
