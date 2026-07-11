# Module: `security`

Capa de seguridad perimetral y de identidad de Spark Match para Fase 1.

## Recursos que crea

| Recurso | Nombre | Para qué |
|---|---|---|
| `aws_kms_key` | `alias/spark-match-{env}-main` | CMK para cifrado de SSM parameters, Secrets Manager, S3 server-side, CloudWatch Logs |
| `aws_security_group` | `spark-match-sg-lambda-{env}` | Egress-only para todas las Lambdas del backend (VPC CIDR + internet 443) |
| `aws_security_group` | `spark-match-sg-rds-{env}` | Ingress 5432 desde `sg-lambda-{env}` para Aurora |
| `aws_security_group` | `spark-match-sg-endpoints-{env}` | Ingress 443 desde `sg-lambda-{env}` para VPC interface endpoints |
| `aws_iam_role` (OIDC) | `spark-match-sam-deploy` | Asumido por `01-devops/sam-deploy.yml` en `03-backend` |
| `aws_iam_role` (OIDC) | `spark-match-bedrock-agentcore-deploy` | Asumido por futuros deploys del agente |
| `aws_iam_role` | `spark-match-lambda-runtime-{env}` | Execution role de las Lambdas |
| `aws_iam_role` | `spark-match-agentcore-runtime-{env}` | Execution role del contenedor FastAPI |

## Inputs clave

| Variable | Default | Descripción |
|---|---|---|
| `vpc_id` | (required) | ID de la VPC donde se crean los SGs (output de `modules/networking`) |
| `vpc_cidr` | `10.0.0.0/16` | CIDR de la VPC (para el egress rule del SG de Lambdas) |
| `kms_deletion_window_in_days` | `30` | Período de gracia para borrar la CMK |
| `sam_deploy_github_repos` | `[spark-match/spark-match-03-backend]` | Repos permitidos en el trust policy de `spark-match-sam-deploy` |
| `bedrock_deploy_github_repos` | `[spark-match/spark-match-08-deep-agent]` | Repos permitidos en el trust policy del agente |
| `create_*_sg_rules` | `true` | Gates para crear las rules por defecto de cada SG (útil durante bootstrap) |

## Outputs clave

Ver `outputs.tf`. Los más usados desde `live/prod/main.tf`:

- `aws_kms_key.main.arn`
- `aws_security_group.lambda.id`
- `aws_security_group.rds.id`
- `aws_security_group.endpoints.id`
- `aws_iam_role.sam_deploy.arn`
- `aws_iam_role.lambda_runtime.arn`
- `aws_iam_role.agentcore_runtime.arn`

## Politicas IAM

Las 4 policies se adjuntan como **inline policies** (vía `aws_iam_role_policy`).
Cada JSON vive en [`docs/policies/`](../../docs/policies/) y se carga via `file()`.

| Rol | Policy | Tamaño |
|---|---|---|
| `spark-match-sam-deploy` | `SamDeployPolicy` | ~9.8 KB (excede límite managed) |
| `spark-match-bedrock-agentcore-deploy` | `BedrockAgentCoreDeployPolicy` | ~4.8 KB |
| `spark-match-lambda-runtime-{env}` | `LambdaRuntimePolicy` | ~3.2 KB |
| `spark-match-agentcore-runtime-{env}` | `AgentCoreRuntimePolicy` | ~3.6 KB |

> Las 4 policies fueron **validadas en AWS IAM real** durante Fase 0 (3 OK,
> 1 sólo OK como inline por tamaño). Para detalle del least-privilege y la
> separación de dominios ver [`docs/IAM_ROLES.md`](../../docs/IAM_ROLES.md).

## Wiring esperado con el resto del repo

```hcl
module "security" {
  source = "../modules/security"

  project_name = "spark-match"
  environment  = "prod"
  vpc_id       = module.networking.vpc_id
  vpc_cidr     = module.networking.vpc_cidr_block

  sam_deploy_github_repos = [
    "spark-match/spark-match-03-backend",
  ]
  bedrock_deploy_github_repos = [
    "spark-match/spark-match-08-deep-agent",
  ]

  tags = local.common_tags
}
```

(Esto NO está aplicado aún; se propone para el PR de Fase 1 una vez que
la composición de `live/prod/main.tf` incorpore `modules/networking`).
