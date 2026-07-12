# Module: `endpoints`

VPC Endpoints para reducir latencia y costos en llamadas desde Lambdas/VPC.

## Interfaz vs gateway

- **Interface endpoint**: cobra $0.01/hora por endpoint ($7.20/mes c/u, us-east-1) + data transfer. Crea ENI en cada subnet donde se monta y expone un DNS privado (`*.amazonaws.com` -> IP privada).
- **Gateway endpoint**: gratis, ruta en la route table. Solo `s3` y `dynamodb` lo soportan.

## Lista de interface endpoints creados por default

| Endpoint | Por qué |
|---|---|
| `ssm`, `ssmmessages`, `ec2messages` | SSM agent (cuando se hace `aws ssm start-session` o se configuran parámetros) |
| `secretsmanager` | `GetSecretValue` desde Lambda (DB creds, JWT secret) |
| `kms` | `Decrypt` para SSM SecureString y Secrets Manager |
| `logs` | Ingesta a CloudWatch Logs (sin costo NAT, ingest directo) |
| `ecr.api`, `ecr.dkr` | Pull de imagen para Lambda containers (mas rapido que atravesando NAT) |
| `bedrock-runtime` | `InvokeModel` desde el agente en AgentCore (latencia <5 ms) |
| `sts` | `AssumeRole` desde Lambdas/AgentCore si en el futuro aparece cross-account |

## Reduccion de costos

Para dev/staging, `enable_all_endpoints_by_default=false` y `enabled_endpoints`
controla cuales se crean. El minimo viable para arrancar seria:
- `secretsmanager`
- `kms`
- `logs`
- `ecr.api`, `ecr.dkr` (cold start Lambdas container)

El resto se agrega a medida que se justifica.

## Wiring esperado

```hcl
module "endpoints" {
  source = "../modules/endpoints"

  project_name = "spark-match"
  environment  = "prod"
  aws_region   = "us-east-1"

  vpc_id                      = module.networking.vpc_id
  private_subnet_ids          = module.networking.private_subnet_ids
  private_route_table_ids     = module.networking.private_route_table_ids
  endpoints_security_group_id = module.security.sg_endpoints_id

  enable_s3_gateway_endpoint      = true
  enable_all_endpoints_by_default = true
  tags = local.common_tags
}
```

(Esto NO esta aplicado aun; queda propuesto para el PR de Fase 1.)
