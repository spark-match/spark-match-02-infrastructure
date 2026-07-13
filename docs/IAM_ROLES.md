# IAM Roles por dominio — Spark Match

> **Estado:** Diseño (Fase 1). Los archivos JSON son **referencia**; los roles se
> aprovisionan via `modules/security` (Terraform) cuando se ejecute el primer
> `terraform apply` (Fase 1.5).
>
> **Principio rector:** un role por **dominio de capacidad** × **ambiente**. El
> repo caller y el ambiente se validan en el **`sub` claim** del OIDC token.

---

## Multi-env: matriz de roles

> **Estrategia:** cada role IAM OIDC de deploy (SAM, Bedrock AgentCore) lleva
> el sufijo `-{env}` y solo acepta `sub` claims para ESE ambiente específico.
> Un token OIDC emitido para `environment:dev` NO puede asumir un role
> `spark-match-sam-deploy-prod`.

| Dominio | dev ARN | prod ARN |
|---|---|---|
| **SAM deploy** (CFN, Lambda, API GW, Events, IAM PassRole) | `arn:aws:iam::681526276858:role/spark-match-sam-deploy-dev` | `arn:aws:iam::681526276858:role/spark-match-sam-deploy-prod` |
| **Bedrock AgentCore deploy** (ECR, Bedrock, AgentCore, IAM PassRole) | `arn:aws:iam::681526276858:role/spark-match-bedrock-agentcore-deploy-dev` | `arn:aws:iam::681526276858:role/spark-match-bedrock-agentcore-deploy-prod` |
| **Lambda runtime** (execution role de las Lambdas) | `arn:aws:iam::681526276858:role/spark-match-lambda-runtime-dev` | `arn:aws:iam::681526276858:role/spark-match-lambda-runtime-prod` |
| **AgentCore runtime** (execution role del contenedor) | `arn:aws:iam::681526276858:role/spark-match-agentcore-runtime-dev` | `arn:aws:iam::681526276858:role/spark-match-agentcore-runtime-prod` |

> Roles de Terraform plan/apply (`spark-match-terraform-{plan,apply}`) son
> compartidos entre dev y prod. Su trust policy restringe por branch y
> `environment`, y el aislamiento real entre envs se logra con buckets S3
> separados, keys separadas y GH Environments con reviewers distintos.

---

## Roles Terraform plan/apply (existentes, no modificar)

| Role | Propósito | Repo autorizado en `sub` | Multi-env |
|---|---|---|---|
| `spark-match-terraform-plan-dev` | `terraform plan` con permisos **read-only** | `spark-match-02-infrastructure` | Acepta `environment:dev` y `ref:refs/heads/dev` |
| `spark-match-terraform-apply-dev` | `terraform apply` con permisos **write** sobre red, S3, IAM base, KMS | `spark-match-02-infrastructure` | Acepta `environment:dev` y `ref:refs/heads/dev` |
| `spark-match-terraform-plan-prod` | `terraform plan` con permisos **read-only** sobre `spark-match-tfstate-prod` | `spark-match-02-infrastructure` | Acepta `environment:production` y `ref:refs/heads/main` |
| `spark-match-terraform-apply-prod` | `terraform apply` con permisos **write** sobre `spark-match-tfstate-prod` + EC2/KMS/IAM create + Logs prod | `spark-match-02-infrastructure` | Acepta `environment:production` y `ref:refs/heads/main` |

> Los 4 roles se actualizaron en Fase 1.5 para incluir `workflow_dispatch` y
> `pull_request` además de los patterns específicos por env. **No se
> separan funcionalmente por env** (excepto los ARN) porque estos roles solo
> aplican cambios a la infra (network, IAM), y el aislamiento entre envs
> está en el state bucket separado y en los GH Environments con branch
> policies.

---

## Roles nuevos (a crear via `modules/security` en Fase 1.5)

Cada role cumple un único fin de negocio. La trust policy limita `sub` al
**repo + ambiente** correspondiente para que un PR a un repo distinto, o un
token emitido para otro env, **no puedan** asumir el role.

### `spark-match-sam-deploy-{dev|prod}`

> **Asumido por:** GitHub Actions en `spark-match/spark-match-03-backend`
> cuando corre `sam deploy` (vía reusable `01-devops/sam-deploy.yml`).
> El role se crea 1 vez por env al aplicar `modules/security` con
> `var.environment = "dev"` o `var.environment = "prod"`.

#### Trust policy (resumen; sub claim estricto por env)

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::681526276858:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": [
        "repo:spark-match/spark-match-03-backend:ref:refs/heads/dev",
        "repo:spark-match/spark-match-03-backend:ref:refs/heads/main",
        "repo:spark-match/spark-match-03-backend:environment:${var.environment}"
      ]
    }
  }
}
```

> Nota: `${var.environment}` se sustituye al aplicar el módulo. El role dev
> solo acepta `environment:dev`; el role prod solo acepta `environment:production`.

#### Política inline `SamDeployPolicy`

Acciones agrupadas, recursos limitados por prefijo. JSON completo en
[`policies/spark-match-sam-deploy.json`](./policies/spark-match-sam-deploy.json).

Resumen por servicio:

| Servicio | Acciones | Recurso scope |
|---|---|---|
| **CloudFormation** | `CreateStack`, `UpdateStack`, `DeleteStack`, `DescribeStacks`, `ListStackResources`, `GetTemplate`, `GetTemplateSummary`, `CreateChangeSet`, `ExecuteChangeSet`, `DeleteChangeSet`, `DescribeChangeSet`, `ContinueUpdateRollback`, `RollbackStack` | `arn:aws:cloudformation:us-east-1:681526276858:stack/spark-match-backend-*/ *` |
| **CloudFormation** (lecturas globales) | `ListStacks`, `DescribeStackEvents`, `DescribeStackResource`, `DescribeStackResources` | `*` |
| **Lambda** | `CreateFunction`, `UpdateFunctionCode`, `UpdateFunctionConfiguration`, `DeleteFunction`, `GetFunction`, `GetFunctionConfiguration`, `ListFunctions`, `CreateEventSourceMapping`, `DeleteEventSourceMapping`, `UpdateEventSourceMapping`, `ListEventSourceMappings`, `AddPermission`, `RemovePermission`, `GetPolicy`, `PutFunctionConcurrency`, `DeleteFunctionConcurrency`, `PublishVersion`, `CreateAlias`, `UpdateAlias` | `arn:aws:lambda:us-east-1:681526276858:function:spark-match-backend-*` + `arn:aws:lambda:us-east-1:681526276858:function:spark-match-backend-*:*` |
| **Lambda Layer** | `GetLayerVersion`, `ListLayerVersions`, `PublishLayerVersion`, `DeleteLayerVersion` | `arn:aws:lambda:us-east-1:681526276858:layer:spark-match-*:*` |
| **API Gateway HTTP v2** | `CreateApi`, `UpdateApi`, `DeleteApi`, `GetApi`, `ImportApi`, `CreateRoute`, `UpdateRoute`, `DeleteRoute`, `CreateIntegration`, `UpdateIntegration`, `DeleteIntegration`, `CreateStage`, `UpdateStage`, `DeleteStage`, `CreateDeployment`, `GetDeployments`, `CreateVpcLink`, `DeleteVpcLink` | `*` (HTTP API v2 ARN no soporta wildcards de resource en todas las acciones) |
| **API Gateway v2** (tag/permission) | `AddTagsToResource`, `RemoveTagsFromResource`, `CreateAuthorizer`, `DeleteAuthorizer`, `UpdateAuthorizer` | `*` |
| **EventBridge** | `PutRule`, `DeleteRule`, `DescribeRule`, `ListRules`, `ListTargetsByRule`, `PutTargets`, `RemoveTargets`, `EnableRule`, `DisableRule`, `PutArchive`, `DeleteArchive`, `DescribeArchive`, `ListArchives`, `CreateArchive` | `arn:aws:events:us-east-1:681526276858:rule/spark-match-*` + `arn:aws:events:us-east-1:681526276858:event-bus/spark-match-*` + `arn:aws:events:us-east-1:681526276858:archive/spark-match-*` |
| **IAM** | `CreateRole`, `DeleteRole`, `GetRole`, `UpdateRole`, `TagRole`, `UntagRole`, `PutRolePolicy`, `DeleteRolePolicy`, `GetRolePolicy`, `ListRolePolicies`, `ListAttachedRolePolicies`, `AttachRolePolicy`, `DetachRolePolicy`, `CreateServiceLinkedRole` | `arn:aws:iam::681526276858:role/spark-match-backend-*` + `arn:aws:iam::681526276858:role/spark-match-backend-*-exec-*` + `arn:aws:iam::681526276858:policy/spark-match-backend-*` (gestionadas en el repo, no AWS-managed) |
| **IAM PassRole** | `iam:PassRole` con condición de servicio destino específico | igual que arriba, sólo `lambda.amazonaws.com`, `apigateway.amazonaws.com`, `events.amazonaws.com` |
| **S3 (artifacts SAM)** | `GetObject`, `PutObject`, `DeleteObject`, `ListBucket`, `GetBucketVersioning`, `GetEncryptionConfiguration` | `arn:aws:s3:::spark-match-sam-artifacts-*` + `arn:aws:s3:::spark-match-sam-artifacts-*/*` |
| **S3 (lambda deployment packages si SAM los empaqueta local)** | `GetObject`, `PutObject` | `arn:aws:s3:::spark-match-backend-deploy-*/*` |
| **SSM** | `GetParameter`, `GetParameters`, `GetParametersByPath` | `arn:aws:ssm:us-east-1:681526276858:parameter/spark-match/*` |
| **KMS** | `Decrypt`, `GenerateDataKey`, `DescribeKey` | `arn:aws:kms:us-east-1:681526276858:key/*` con condición `"aws:ResourceTag/Project": "spark-match"` |
| **CloudWatch Logs** | `CreateLogGroup`, `DeleteLogGroup`, `DescribeLogGroups`, `CreateLogStream`, `DeleteLogStream`, `PutRetentionPolicy`, `TagResource`, `UntagResource`, `PutSubscriptionFilter` | `arn:aws:logs:us-east-1:681526276858:log-group:/aws/spark-match/backend/*` + `arn:aws:logs:us-east-1:681526276858:log-group:/aws/lambda/spark-match-backend-*` |
| **X-Ray** | `PutTraceSegments`, `PutTelemetryRecords`, `GetTraceSummaries`, `BatchGetTraces` | `*` (X-Ray no soporta resource scoping razonable) |
| **STS** | `GetCallerIdentity` | `*` (necesario para validar identidad en logs) |
| **CloudFront** (sólo si se agrega el módulo `cdn`) | `CreateDistribution`, `UpdateDistribution`, `DeleteDistribution` | `*` (opcional, gate por variable) |
| **SQS** (DLQ que SAM crea vía template) | `CreateQueue`, `DeleteQueue`, `GetQueueAttributes`, `SetQueueAttributes`, `AddPermission`, `RemovePermission`, `TagQueue`, `UntagQueue` | `arn:aws:sqs:us-east-1:681526276858:spark-match-backend-*` |

> **Nota de scope:** muchas acciones de API Gateway HTTP v2, X-Ray y EC2 no
> soportan ARN-based resource control. Se mantiene `Resource: "*"` con el
> compromiso de que el role SOLO es invocable desde el trust policy
> restringido al repo `03-backend`.

---

### `spark-match-bedrock-agentcore-deploy-{dev|prod}`

> **Asumido por:** GitHub Actions en `spark-match/spark-match-08-deep-agent`
> cuando corre `docker build + push` a ECR y `agentcore deploy`. Misma lógica
> de sufijo por env que `sam-deploy`.

#### Trust policy (resumen; sub claim estricto por env)

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::681526276858:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": [
        "repo:spark-match/spark-match-08-deep-agent:ref:refs/heads/dev",
        "repo:spark-match/spark-match-08-deep-agent:ref:refs/heads/main",
        "repo:spark-match/spark-match-08-deep-agent:environment:${var.environment}"
      ]
    }
  }
}
```

#### Política inline `BedrockAgentCoreDeployPolicy`

Acciones agrupadas, recursos limitados por prefijo. JSON completo en
[`policies/spark-match-bedrock-agentcore-deploy.json`](./policies/spark-match-bedrock-agentcore-deploy.json).

| Servicio | Acciones | Recurso scope |
|---|---|---|
| **ECR** | `CreateRepository`, `DeleteRepository`, `DescribeRepositories`, `GetRepositoryPolicy`, `SetRepositoryPolicy`, `DeleteRepositoryPolicy`, `PutImage`, `InitiateLayerUpload`, `UploadLayerPart`, `CompleteLayerUpload`, `BatchGetImage`, `BatchCheckLayerAvailability`, `GetDownloadUrlForLayer`, `ListImages`, `PutImageScanningConfiguration`, `PutImageTagMutability`, `PutLifecyclePolicy`, `StartImageScan`, `GetImageScanFindings` | `arn:aws:ecr:us-east-1:681526276858:repository/spark-match-agent-*` |
| **ECR auth** | `GetAuthorizationToken` | `*` (ECR GetAuthorizationToken no soporta resource scoping) |
| **Bedrock** (invocación desde el deploy job para smoke test) | `InvokeModel`, `InvokeModelWithResponseStream`, `ListFoundationModels`, `GetFoundationModel` | `arn:aws:bedrock:us-east-1:681526276858:foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0` (modelo default) |
| **Bedrock AgentCore Runtime** *(permisos a confirmar contra la API final del servicio; AgentCore está en preview en us-east-1 al cierre del 2026)* | acciones `CreateRuntime`, `UpdateRuntime`, `DeleteRuntime`, `GetRuntime`, `ListRuntimes`, `InvokeAgentRuntime`, `StartRuntimeSession`, `StopRuntimeSession` + lecturas | pendiente de mapeo exacto (verificar `aws bedrock-agentcorecontrol` y `aws bedrock-agentcoreruntime` con `aws <svc> help` antes de Fase 4) |
| **CloudWatch Logs** | mismos que `spark-match-sam-deploy` | `arn:aws:logs:us-east-1:681526276858:log-group:/aws/spark-match/agent/*` + `arn:aws:logs:us-east-1:681526276858:log-group:/aws/bedrock-agentcore/spark-match-*` |
| **IAM PassRole** | `iam:PassRole` para que AgentCore pueda asumir el execution role del contenedor | `arn:aws:iam::681526276858:role/spark-match-agentcore-exec-*` con `iam:PassedToService = bedrock-agentcore.amazonaws.com` |
| **IAM** | `CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `TagRole`, `GetRole` para crear el execution role on-demand (opcional) | `arn:aws:iam::681526276858:role/spark-match-agentcore-exec-*` |
| **KMS** | `Decrypt`, `GenerateDataKey`, `DescribeKey` para descifrar env vars encriptadas | `arn:aws:kms:us-east-1:681526276858:key/*` con condición `aws:ResourceTag/Project = spark-match` |
| **SSM** | `GetParameter`, `GetParameters`, `GetParametersByPath` | `arn:aws:ssm:us-east-1:681526276858:parameter/spark-match/*` |
| **Secrets Manager** | `GetSecretValue` (para runtime env vars) | `arn:aws:secretsmanager:us-east-1:681526276858:secret:spark-match/agent-*` |
| **STS** | `GetCallerIdentity` | `*` |

> **Riesgo conocido:** Los ARN de `bedrock-agentcorecontrol` /
> `bedrock-agentcoreruntime` no están todavía **listados en esta doc** porque el
> servicio es **preview** en `us-east-1`. Antes de Fase 4 hay que ejecutar
> `aws bedrock-agentcorecontrol help` y `aws bedrock-agentcoreruntime help`
> para capturar el set de acciones y traducirlas a IAM. Esta política se
> completará en ese punto.

---

### `spark-match-lambda-runtime-{env}` (execution role de las Lambdas del backend)

> NO es un role de OIDC. Es el **execution role** que las Lambdas de
> `spark-match-backend-*` asumen. Lo crea `modules/security` con sufijo
> `{var.environment}` y es **referenciado** desde `template.yaml` y desde
> `spark-match-sam-deploy-{env}` via PassRole.

| Permiso | Recurso | Por qué |
|---|---|---|
| `AWSLambdaBasicExecutionRole` (managed) | — | Logs a CloudWatch |
| `AWSLambdaVPCAccessExecutionRole` (managed) | — | ENI en la VPC de Lambdas |
| `AWSXRayDaemonWriteAccess` (managed) | — | Traces a X-Ray |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:us-east-1:681526276858:secret:spark-match/backend-*` | DB creds, JWT secret |
| `ssm:GetParameter`, `ssm:GetParameters` | `arn:aws:ssm:us-east-1:681526276858:parameter/spark-match/*` | SSM bridge (event bus ARN, etc.) |
| `events:PutEvents` | `arn:aws:events:us-east-1:681526276858:event-bus/spark-match-events-*` | Emitir eventos de dominio |
| `dynamodb:GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `Query`, `Scan` | `arn:aws:dynamodb:us-east-1:681526276858:table/spark-match-backend-*` + `table/*/index/*` | Idempotency table |
| `kms:Decrypt` | `arn:aws:kms:us-east-1:681526276858:key/*` con tag `Project=spark-match` | Desencriptar env vars |
| `s3:GetObject`, `PutObject`, `DeleteObject` (sólo matching) | `arn:aws:s3:::spark-match-rag-documents-*/*` | RAG documents (si aplica) |
| `rds:*` con scope por tag | `arn:aws:rds:us-east-1:681526276858:cluster:spark-match-aurora-*` | Sólo lectura de tags |

Trust policy: `lambda.amazonaws.com` con `SourceAccount=681526276858`.

---

### `spark-match-agentcore-runtime-{env}` (execution role del agente en AgentCore)

> Tampoco es un role OIDC. Es el execution role del contenedor FastAPI cuando
> corre en Bedrock AgentCore Runtime. Lo crea `modules/security` con sufijo
> `{var.environment}` (Fase 1) y `modules/bedrock` lo referencia (Fase 4).

| Permiso | Recurso | Por qué |
|---|---|---|
| `CloudWatchAgentServerPolicy` + Logs write | `/aws/spark-match/agent/*` | Logs del agente |
| `AWSXRayDaemonWriteAccess` | — | Traces |
| `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream` | `arn:aws:bedrock:us-east-1:681526276858:foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0` y `anthropic.claude-haiku-4-5-20251001-v1:0` | Llamar al LLM |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:us-east-1:681526276858:secret:spark-match/agent-*` | Tavily key, LangSmith key |
| `ssm:GetParameter`, `ssm:GetParameters` | `arn:aws:ssm:us-east-1:681526276858:parameter/spark-match/*` | Config runtime |
| `rds-data:ExecuteStatement`, `BatchExecuteStatement` | cluster taggeado `Project=spark-match` | pgvector en Aurora |
| `secretsmanager:CreateSecret`, `PutSecretValue` (sólo si el agente escribe per-user memory) | `arn:aws:secretsmanager:us-east-1:681526276858:secret:spark-match/agent-user-*` | Memoria cross-session |
| `tavily` y `langsmith` vía OUTBOUND HTTPS | n/a (egress 443) | ya cubierto por SG/egress |

Trust policy: servicio destino `bedrock-agentcore.amazonaws.com` con
`SourceAccount=681526276858`.

---

## Variables Terraform (cómo se invoca `modules/security`)

```hcl
# En live/dev/main.tf y live/prod/main.tf (preview Fase 1.5)

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment  # "dev" o "prod"
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = module.networking.vpc_cidr_block

  # Repos autorizados por role. El modulo genera sub claim patterns por env.
  sam_deploy_github_repos = [
    "spark-match/spark-match-03-backend",
  ]

  bedrock_deploy_github_repos = [
    "spark-match/spark-match-08-deep-agent",
  ]

  # KMS: 7 dias dev, 30 prod
  kms_deletion_window_in_days = var.environment == "prod" ? 30 : 7

  # Reglas de SG vacias durante bootstrap (se prenden via flag en modulos futuros)
  create_lambda_sg_rules    = false
  create_rds_sg_rules       = false
  create_endpoints_sg_rules = false

  tags = local.common_tags
}
```

---

## Diagrama de confianza multi-env

```
                         token.actions.githubusercontent.com
                                       │ (OIDC, ya configurado)
                                       ▼
                        +-----------------------------+
                        |     IAM Identity Provider   |
                        |  thumbprint 6938fd4d...    |
                        +-----------------------------+
                                       │
        sub: 02-infra:env:{dev|prod}   │  sub: 03-backend:env:{dev|prod}    sub: 08-deep-agent:env:{dev|prod}
                                       ▼
        +-------------------+   +----------------------------+   +----------------------------+
        | terraform-plan    |   | spark-match-sam-deploy-   |   | spark-match-bedrock-       |
        | terraform-apply   |   | {dev|prod}                 |   | agentcore-deploy-{dev|prod}|
        | (NO TOCAR)        |   | (CFN, Lambda, API GW,      |   | (ECR, Bedrock, AgentCore,  |
        +-------------------+   |  Events, IAM PassRole,     |   |  IAM PassRole, KMS, SSM,   |
                                |  S3, KMS, CW, X-Ray)       |   |  Secrets)                  |
                                +----------------------------+   +----------------------------+
                                          │ PassRole                  │ PassRole
                                          ▼                            ▼
                                +----------------------------+   +----------------------------+
                                | spark-match-lambda-        |   | spark-match-agentcore-     |
                                | runtime-{dev|prod}         |   | runtime-{dev|prod}         |
                                | (logs, X-Ray, SSM,         |   | (Bedrock Invoke, Secrets,  |
                                |  Secrets, Events, DDB,     |   |  SSM, RDS-data, CW Logs,    |
                                |  KMS, RDS, S3)             |   |  X-Ray)                    |
                                +----------------------------+   +----------------------------+
```

---

## ¿Por qué separar roles SAM/Bedrock-deploy por env (estricto)?

1. **Principio de menor privilegio:** un role de deploy `sam-deploy-prod`
   solo puede ser invocado por un workflow que tenga `environment:production`
   en su `sub` claim. Si el `sub` dice `environment:dev`, la asunción es
   rechazada por AWS antes de conceder ningún permiso.

2. **Aislamiento de blast radius:** un PR a la rama `dev` en `03-backend`
   puede deployar **solo a dev**, no a prod. Si alguien pushea código malicioso
   a `dev`, el role `sam-deploy-dev` puede hacer daño solo al ambiente dev.

3. **Auditoría limpia:** CloudTrail muestra
   `role-session-name=github-actions-sam-deploy-dev-...` vs `...-prod-...`.
   Filtrar por env es trivial en cualquier consulta de auditoría.

4. **Costo de la separación:** 4 roles extra (sam-deploy-dev, sam-deploy-prod,
   bedrock-deploy-dev, bedrock-deploy-prod). Costo: $0 (roles IAM son gratis).
   Beneficio: aislamiento total por env.

---

## ¿Por qué NO separar el role Terraform plan/apply por env?

1. **Estos roles solo se usan desde el repo `02-infrastructure`** para crear
   la infra. No se usan por apps de runtime.
2. **El aislamiento real entre envs está en otra capa:** buckets S3 separados,
   keys separadas, GH Environments con reviewers distintos, branch policies.
3. **Reducir superficie IAM:** mantener 2 roles (vs 4) reduce la cantidad de
   trust policies que mantener y validar.
4. **El trust policy ya restringe por branch + environment**: un token con
   `environment:dev` solo puede planificar/aplicar lo que el bucket
   `spark-match-tfstate-dev` contiene.

---

## Pasos para aplicar este diseño en Fase 1.5

1. ~~Crear `02-infrastructure/modules/security/{main.tf,variables.tf,outputs.tf,policies/}`~~ ✅ Hecho
2. ~~Crear los policies JSON en `policies/*.json`~~ ✅ Hecho
3. ~~Crear los módulos `networking` y `endpoints`~~ ✅ Hecho
4. ⏳ Componer `live/dev/main.tf` y `live/prod/main.tf` con la composición de módulos
5. ⏳ Primer `terraform plan` (debe mostrar los 4 roles IAM nuevos por env)
6. ⏳ Primer `terraform apply` desde `live/dev` (crea roles dev + KMS dev + VPC dev + endpoints dev)
7. ⏳ Validar que `aws sts assume-role-with-web-identity` funciona con un token de prueba
8. ⏳ Repetir para prod con merge a `main` + approval
9. ⏳ Configurar los GitHub Secrets en `03-backend` y `08-deep-agent`:
   - `03-backend` → `AWS_SAM_DEPLOY_ROLE_ARN` (valor: `arn:...:spark-match-sam-deploy-{env}`)
   - `08-deep-agent` → `AWS_BEDROCK_AGENTCORE_DEPLOY_ROLE_ARN` (valor: `arn:...:spark-match-bedrock-agentcore-deploy-{env}`)
10. ⏳ Crear los GH Environments `dev` y `production` en `03-backend` y `08-deep-agent`
11. ⏳ Validar el flujo end-to-end: push a `dev` → deploy a AWS dev

---

## Glosario

- **Trust policy** → bloque JSON dentro de un IAM role que define **quién puede
  asumirlo**. Aquí siempre es el OIDC provider de GitHub con condición sobre el
  `sub` claim.
- **Inline policy** → JSON de permisos **adjunto** al role directamente. No es
  una managed policy porque cada role tiene políticas únicas y no se comparten
  entre accounts.
- **Least privilege** → dar **solo** las acciones y recursos estrictamente
  necesarios para la tarea. Aquí: cada role tiene un ARN pattern de recurso
  con prefijo `spark-match-*` para no tocar recursos de otros proyectos.
- **`sub` claim** → campo del JWT de OIDC que identifica el
  `repo:owner/name:ref:refs/heads/<branch>` o
  `repo:owner/name:pull_request` o
  `repo:owner/name:environment:<env>`. Es la **puerta de entrada** del trust
  policy.
- **Estrategia estricta por env** → cada role IAM lleva el sufijo del ambiente
  (`-dev`, `-prod`) y su trust policy SOLO acepta tokens emitidos para ESE
  ambiente. Imposible confundir deploys entre envs.

## Decision documentada: por que el trust policy incluye `ref:refs/heads/*` ademas de `environment:*`

Ref: IMPROVEMENTS.md [SEC-04]

Los trust policies de `spark-match-sam-deploy-{env}` y
`spark-match-bedrock-agentcore-deploy-{env}` aceptan 3 tipos de `sub` claim:

1. `repo:<repo>:ref:refs/heads/dev`
2. `repo:<repo>:ref:refs/heads/main`
3. `repo:<repo>:environment:${environment}`

**Por que NO removemos los patterns `ref:refs/heads/*` y dejamos solo `environment:*`:**

El workflow `terraform-plan.yml` (caller de `02-infrastructure`) corre en
`pull_request` contra `dev` o `main`. Ese job NO se asocia a un GH Environment,
por lo que el token OIDC emitido por GitHub Actions **no contiene** el claim
`environment:`. Solo contiene `ref:refs/heads/<branch>` y `pull_request`.

Si removemos los patterns `ref:refs/heads/*`, el `terraform plan` en PRs
no podria asumir el role de plan, y el CI se romperia (no se podria validar
un PR antes de mergear).

**Trade-off aceptado:**

- (+) El plan en PRs funciona sin requerir un environment explicito.
- (-) Un token emitido por un push directo a `dev` o `main` (sin pasar por
  un environment) puede asumir el role. Esto en la practica esta mitigado
  por el ruleset del repo: `non_fast_forward` y `required_linear_history`
  bloquean force-pushes, y el CODE OWNER de devops es requerido para aprobar
  cualquier PR contra `dev` o `main`.

**Alternativa futura:** si el equipo decide endurecer mas, se podria crear
un GH Environment "plan-dev" y "plan-prod" sin required reviewers, y mover
el caller `terraform-plan.yml` para usar `environment: plan-dev` en el job
`plan-pr`. Esto permitiria remover los patterns `ref:refs/heads/*`. Pero
es un cambio de workflow que requiere decision explicita del equipo.

**Conclusion:** mantenemos los 3 patterns. La decision queda registrada en
este documento (trazabilidad) y en el codigo de
`modules/security/main.tf` (comentario sobre los `sam_deploy_sub_patterns`
y `bedrock_deploy_sub_patterns`).
