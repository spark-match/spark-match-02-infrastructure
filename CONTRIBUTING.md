# Contributing - Spark Match Infrastructure (02)

## Overview

Este repositorio define la infraestructura AWS multi-ambiente (dev + prod) del
proyecto Spark Match, usando Terraform modular y workflows reutilizables desde
`spark-match-01-devops`.

## Ambientes

| Ambiente | Branch | GH Environment | AWS Account      | Region   | Costo networking |
| -------- | ------ | -------------- | ---------------- | -------- | ---------------- |
| dev      | dev    | dev            | 681526276858     | us-east-1 | $0/mes (Opcion A: Lambdas fuera de VPC) |
| prod     | main   | production     | 681526276858     | us-east-1 | ~$75-82/mes (NAT HA + 10 endpoints)     |

## Workflow de cambios

1. **Crear rama desde dev** con prefijo semantico:
   - `feat/<descripcion-corta>` para nuevas features
   - `fix/<descripcion-corta>` para bugfixes
   - `chore/<descripcion-corta>` para housekeeping
   - `docs/<descripcion-corta>` para documentacion

2. **Hacer cambios pequenos y enfocados**. Un PR = un commit logico.

3. **Validar localmente**:
   ```bash
   # Desde la raiz del repo
   pre-commit run --all-files

   # Validar Terraform
   cd live/dev
   terraform init -backend=false
   terraform validate
   cd ../prod
   terraform init -backend=false
   terraform validate
   ```

4. **Push a dev y abrir PR**:
   - El PR dispara `CI - Terraform Plan` automaticamente (Plan dev).
   - Resolver el review de CODEOWNERS (ver `.github/CODEOWNERS`).
   - Esperar el check `Plan (dev) / Plan (dev)` en verde.

5. **Merge via squash** (unico metodo de merge permitido por ruleset).

6. **Sync a main**: el autor del PR hace push directo a main via
   `git push --force-with-lease origin chore/sync-dev-to-main-...:main`
   solo si el cambio es una consolidacion. Para cambios de codigo, abrir
   PR contra main con aprobacion.

## Secrets y variables de entorno

| Secret                     | Uso                                          |
| -------------------------- | -------------------------------------------- |
| `AWS_PLAN_ROLE_ARN_DEV`    | OIDC role para `terraform plan` en dev        |
| `AWS_PLAN_ROLE_ARN_PROD`   | OIDC role para `terraform plan` en prod       |
| `AWS_APPLY_ROLE_ARN_DEV`   | OIDC role para `terraform apply` en dev       |
| `AWS_APPLY_ROLE_ARN_PROD`  | OIDC role para `terraform apply` en prod      |

Los roles OIDC son especificos por ambiente y tienen trust policy restringido
a la combinacion repo+branch+environment correspondiente.

## Convenciones Terraform

- **Provider**: AWS ~> 5.40 (fijo en `live/*/versions.tf` y
  `modules/*/versions.tf`).
- **Backend**: S3 + DynamoDB (legacy) o S3 native lockfile (preferido). El
  bucket de state es especifico por ambiente (`spark-match-tfstate-{env}`).
- **Tagging**: aplicar `default_tags` a nivel de provider (definido en
  `live/*/providers.tf`). Tags obligatorios: `Project=spark-match`,
  `Environment={dev|prod}`, `ManagedBy=terraform`.
- **Naming**: prefijo `spark-match-{componente}-{env}-` para todos los
  recursos creados fuera de los modulos.
- **Politicas IAM**: parametrizar por `${var.environment}` via `templatefile()`.
  NUNCA hardcodear el ambiente en un JSON.

## Estructura del repositorio

```
.
├── .github/
│   ├── CODEOWNERS
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/                 # Callers que invocan reusables de 01-devops
├── docs/
│   ├── IAM_ROLES.md               # Diseno de roles IAM y politicas
│   └── policies/{dev,prod}/       # 4 politicas IAM x 2 ambientes = 8 JSON
├── live/
│   ├── dev/                       # Root module dev
│   └── prod/                      # Root module prod
├── modules/
│   ├── networking/                # VPC, subnets, NAT, IGW, EIPs
│   ├── security/                  # IAM, KMS, Security Groups, OIDC
│   └── endpoints/                 # VPC interface endpoints
└── scripts/
    ├── apply.sh                   # Wrapper para terraform apply
    ├── destroy.sh                 # Wrapper para terraform destroy
    ├── plan.sh                    # Wrapper para terraform plan
    ├── bootstrap-backend.sh       # Crear bucket S3 de state por ambiente
    └── generate-policies.ps1      # Regenerar policies IAM per-env
```

## Antes del primer apply

Consultar `D:\UNI\Spark\IMPROVEMENTS.md` y `D:\UNI\Spark\PLAN_MULTI_ENV.md`
para el contexto completo. El apply directo a AWS aun NO se ha ejecutado
sobre esta cuenta, asi que los cambios a IAM/networking se pueden hacer
sin migracion.

## Contacto

- Slack: `#spark-match-infra`
- Code owners: ver `.github/CODEOWNERS`
