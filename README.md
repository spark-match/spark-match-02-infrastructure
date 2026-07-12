# Spark Match — Infraestructura como Código

Infraestructura AWS del proyecto **Spark Match** (Copiloto de Orientación Vocacional con IA Generativa), gestionada con **Terraform puro**.

> Repositorio: [spark-match/spark-match-02-infrastructure](https://github.com/spark-match/spark-match-02-infrastructure)
> Propietario: `@spark-match/devops`

---

## Stack

- **Cloud:** AWS (`us-east-1`)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 (state) + S3 native lockfile (sin DynamoDB), un bucket por ambiente
- **Linting:** `tflint`, `terraform fmt`, `pre-commit-terraform`
- **CI/CD:** GitHub Actions con **OIDC** hacia AWS (roles separados plan/apply)
- **Pipelines:** [Reusable workflows](https://github.com/spark-match/spark-match-01-devops) desde `spark-match-01-devops`

---

## Estado actual (Fase 0 cerrada)

Cuenta `681526276858`, región `us-east-1`. Estado validado contra AWS:

- **Aplicado:** 2 buckets de state (`spark-match-tfstate-dev`, `spark-match-tfstate-prod`) con versionado + AES256 + PAB + lockfile nativo; OIDC provider de GitHub; **4 IAM roles OIDC** (`spark-match-terraform-{plan,apply}-{dev,prod}`) con trust policy estricto por env; 4 GH Secrets (`AWS_{PLAN,APPLY}_ROLE_ARN_{DEV,PROD}`).
- **Aplicado (Fase 1):** módulos `security`, `networking`, `endpoints` escritos y validados con `terraform validate` (sin apply todavía).
- **No aplicado:** cero recursos de Spark Match creados (VPC, secrets, RDS, bus, DDB, Lambda, ECR, CF stacks). Todo es greenfield.

---

## Multi-environment setup (dev + prod)

| Aspecto | dev | prod |
|---|---|---|
| **Branch** | `dev` | `main` |
| **GitHub Environment** | `dev` (sin required reviewers) | `production` (con required reviewers) |
| **State bucket** | `spark-match-tfstate-dev` | `spark-match-tfstate-prod` |
| **State key** | `dev/terraform.tfstate` | `prod/terraform.tfstate` |
| **VPC CIDR** | `10.10.0.0/16` | `10.0.0.0/16` |
| **NAT Gateway** | OFF ($0/mes) | HA en 2 AZs ($64/mes) |
| **VPC Endpoints** | Solo S3 gateway (gratis) | 10 interface endpoints + S3 gateway (~$72/mes) |
| **KMS deletion window** | 7 días | 30 días |
| **Lambda concurrency** | Default 10 | Default 10 |
| **Triggers de apply** | push a `dev`, o `workflow_dispatch` con `environment=dev` | push a `main`, o `workflow_dispatch` con `environment=prod` |

> **CIDR planning**: dev `10.10/16`, prod `10.0/16`. Reservado `10.20/16` para staging futuro. Permite VPC peering / Transit Gateway sin colisiones.

### Diagrama de flujo de cambios

```
PR abierto contra main o dev
  └─> terraform-plan.yml corre matrix [dev, prod]
      ├─> Plan dev: working-dir=live/dev, bucket=spark-match-tfstate-dev
      └─> Plan prod: working-dir=live/prod, bucket=spark-match-tfstate-prod
  └─> Comment sticky en PR con tabla de cambios por env

Merge a dev branch
  └─> terraform-apply.yml -> apply-dev
      └─> GH Environment "dev" (auto, sin reviewers)

Merge a main branch
  └─> terraform-apply.yml -> apply-prod
      └─> GH Environment "production" (requiere aprobacion de @spark-match/devops)
```

---

## Estructura

```
spark-match-02-infrastructure/
|-- modules/                      # Modulos reutilizables de Terraform
|   |-- security/                 # (Fase 1) IAM base roles, KMS keys, security groups
|   |-- networking/               # (Fase 1) VPC, subnets publicas/privadas, NAT
|   |-- endpoints/                # (Fase 1) VPC interface endpoints (SSM, ECR, etc.)
|   |-- database/                 # (Fase 2) RDS Aurora PostgreSQL v2 + pgvector
|   |-- storage/                  # (Fase 2) S3 buckets definitivos
|   |-- events/                   # (Fase 2) EventBridge bus + archive + DLQ
|   |-- secrets/                  # (Fase 2) Secrets Manager (JWT, DB credentials)
|   |-- monitoring/               # (Fase 2) CloudWatch + SNS
|   |-- bedrock/                  # (Fase 4) IAM Bedrock + ECR repo del agente
|-- live/
|   |-- dev/                      # Instancia dev (Fase 0 cerrado)
|   |   |-- main.tf
|   |   |-- variables.tf
|   |   |-- outputs.tf
|   |   |-- versions.tf
|   |   |-- providers.tf
|   |   |-- terraform.tfvars
|   |   |-- terraform.tfvars.example
|   |   |-- .terraform.lock.hcl
|   |-- prod/                     # Instancia productiva
|   |   |-- main.tf
|   |   |-- variables.tf
|   |   |-- outputs.tf
|   |   |-- versions.tf
|   |   |-- providers.tf
|   |   |-- terraform.tfvars
|   |   |-- terraform.tfvars.example
|   |   |-- .terraform.lock.hcl
|-- scripts/
|   |-- bootstrap-backend.sh      # Crea S3 bucket para state (parametrizable por env)
|   |-- plan.sh                   # terraform plan (acepta env como argumento)
|   |-- apply.sh                  # terraform apply (acepta env como argumento)
|   |-- destroy.sh                # terraform destroy (con confirmacion textual)
|-- docs/
|   |-- IAM_ROLES.md              # (Fase 0) Design + JSON policies de roles por dominio
|   |-- policies/                 # JSON de policies para roles IAM del modulo security
|       |-- spark-match-sam-deploy.json
|       |-- spark-match-bedrock-agentcore-deploy.json
|       |-- spark-match-lambda-runtime.json
|       |-- spark-match-agentcore-runtime.json
|-- .github/workflows/
|   |-- terraform-plan.yml        # Caller de reusable (matrix dev + prod)
|   |-- terraform-apply.yml       # Caller de reusable (2 jobs: apply-dev, apply-prod)
|-- .tflint.hcl
|-- .pre-commit-config.yaml
|-- LICENSE
|-- README.md
```

> Los modulos `s3-example` (que era una POC nunca aplicada) y `networking` viejo fueron eliminados por completo durante Fase 0 (recuperables via git history). El `networking` actual se reescribio en Fase 1 con foco en multi-env.

---

## Pre-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.6.0`
- [AWS CLI](https://aws.amazon.com/cli/) configurado con un perfil o variables de entorno
- (Opcional) [pre-commit](https://pre-commit.com/) + [tflint](https://github.com/terraform-linters/tflint)
- (Opcional) [GitHub CLI](https://cli.github.com/) para gestionar secrets y environments

---

## Bootstrap (primera vez por ambiente)

Antes del primer `terraform init` en cada ambiente, crear el bucket S3 para el state remoto. El script es idempotente.

```bash
chmod +x scripts/*.sh

# Bootstrap dev
ENVIRONMENT=dev ./scripts/bootstrap-backend.sh

# Bootstrap prod
ENVIRONMENT=prod ./scripts/bootstrap-backend.sh
```

Esto crea el bucket `spark-match-tfstate-{env}` con:
- Versionado habilitado (obligatorio para state + lockfile)
- Encriptación server-side AES256
- Acceso público bloqueado (4 flags)

> **Locking**: S3 native lockfile (Terraform >= 1.6). NO se crea tabla DynamoDB. Si vienes de versiones anteriores del script que creaba `spark-match-tflock`, esa tabla DynamoDB quedara huerfana y deberas eliminarla manualmente.

### Verificar los buckets manualmente

```bash
aws --profile spark-match --region us-east-1 s3api get-bucket-versioning \
  --bucket spark-match-tfstate-dev

aws --profile spark-match --region us-east-1 s3api get-bucket-encryption \
  --bucket spark-match-tfstate-dev

aws --profile spark-match --region us-east-1 s3api get-public-access-block \
  --bucket spark-match-tfstate-dev
```

---

## Uso diario

### Terraform local (un ambiente)

```bash
cd live/dev   # o live/prod

terraform init -backend-config="bucket=spark-match-tfstate-dev" \
               -backend-config="key=dev/terraform.tfstate" \
               -backend-config="region=us-east-1" \
               -backend-config="use_lockfile=true"

# terraform.tfvars ya viene commiteado con los valores del env
./scripts/plan.sh dev
./scripts/apply.sh dev
```

### Terraform local (ambos ambientes)

```bash
# Planear ambos envs en paralelo (en terminales separadas)
./scripts/plan.sh dev
./scripts/plan.sh prod

# Aplicar uno por uno (con confirmacion interactiva)
./scripts/apply.sh dev
./scripts/apply.sh prod

# Destruir (PELIGROSO, requiere confirmacion textual)
./scripts/destroy.sh dev
./scripts/destroy.sh prod
```

### Con variables de entorno PowerShell (Windows)

```powershell
$env:AWS_PROFILE="spark-match"
$env:AWS_REGION="us-east-1"
$env:AWS_SDK_LOAD_CONFIG="1"   # Necesario para que Terraform lea el perfil

# Dev
cd live/dev
terraform init -backend-config="bucket=spark-match-tfstate-dev" `
               -backend-config="key=dev/terraform.tfstate" `
               -backend-config="region=us-east-1" `
               -backend-config="use_lockfile=true"
terraform plan
```

---

## Workflow de desarrollo

1. Crear rama: `git checkout -b feat/<modulo>-<descripcion>` (desde `dev` o `main`)
2. Editar o agregar módulos en `modules/`
3. Consumir desde `live/dev/main.tf` y/o `live/prod/main.tf`
4. Abrir PR hacia `dev` o `main` → el workflow `terraform-plan.yml` corre matrix [dev, prod] y postea resumen en el PR
5. CODEOWNERS requiere aprobación de `@spark-match/devops`
6. Merge a `dev` → `apply-dev` corre (sin approval, GH env `dev`).
7. Merge a `main` → `apply-prod` corre con approval gate (GH env `production` requiere reviewers).
8. Aprobar el deployment en GitHub UI → `terraform apply` corre.

---

## Añadir un nuevo módulo

1. `mkdir -p modules/<nombre>`
2. Crear `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
3. Agregar un bloque `module "<nombre>"` en `live/dev/main.tf` y `live/prod/main.tf`
4. (Opcional) agregar variables en `live/{dev,prod}/variables.tf` y defaults en `terraform.tfvars`

---

## 🔐 Autenticación AWS: OIDC

Este repositorio usa **OpenID Connect (OIDC)** para que GitHub Actions pueda asumir roles IAM en AWS **sin access keys de larga duración**.

### ¿Por qué OIDC?

| Método | Seguridad | Rotación | Secretos en GitHub |
|---|---|---|---|
| Access keys | Baja (filtrables) | Manual | 2 (key + secret) |
| **OIDC** | Alta (`sts:AssumeRoleWithWebIdentity`) | Automática (1h) | 1 (ARN por role) |

### Arquitectura

```
GitHub Actions runner
  └─> Pide token a GitHub OIDC (token.actions.githubusercontent.com)
      └─> Llama a AWS STS: AssumeRoleWithWebIdentity
          └─> AWS valida:
              - ¿La firma del token es de GitHub?
              - ¿El repo/branch coincide con la trust policy?
          └─> Si OK: devuelve credenciales temporales (1h)
              └─> Terraform puede usar la cuenta AWS
```

### Roles Terraform plan/apply (este repo)

> NOTA: estos roles son SOLO para terraform plan/apply desde el repo `02-infrastructure`. Son DIFERENTES de los roles OIDC que desplegarán SAM y AgentCore (esos viven en `modules/security` y se crean por env).

**Estrategia multi-env estricta**: **4 IAM roles**, uno por `(env, capability)`. Cada role acepta SOLO el `sub` claim de su env específico. Un token OIDC con `environment:dev` NO puede asumir un role `*-prod`.

| Role | ARN | Trust policy | IAM policy | Secret en GitHub |
|---|---|---|---|---|
| `spark-match-terraform-plan-dev` | `arn:aws:iam::681526276858:role/spark-match-terraform-plan-dev` | Solo `environment:dev` + `ref:refs/heads/dev` | Read-only sobre `spark-match-tfstate-dev` + EC2/KMS/IAM describe | `AWS_PLAN_ROLE_ARN_DEV` |
| `spark-match-terraform-apply-dev` | `arn:aws:iam::681526276858:role/spark-match-terraform-apply-dev` | Solo `environment:dev` + `ref:refs/heads/dev` | Write sobre `spark-match-tfstate-dev` + EC2/KMS/IAM create + Logs dev | `AWS_APPLY_ROLE_ARN_DEV` |
| `spark-match-terraform-plan` (prod) | `arn:aws:iam::681526276858:role/spark-match-terraform-plan` | Solo `environment:production` + `ref:refs/heads/main` | Read-only sobre `spark-match-tfstate-prod` + EC2/KMS/IAM describe | `AWS_PLAN_ROLE_ARN_PROD` |
| `spark-match-terraform-apply` (prod) | `arn:aws:iam::681526276858:role/spark-match-terraform-apply` | Solo `environment:production` + `ref:refs/heads/main` | Write sobre `spark-match-tfstate-prod` + EC2/KMS/IAM create + Logs prod | `AWS_APPLY_ROLE_ARN_PROD` |

**Aislamiento real entre envs**:

1. **IAM role**: cada uno tiene trust policy con `StringLike` que SOLO matchea el sub claim de su env.
2. **IAM policy**: cada uno tiene permisos SOLO sobre su bucket + recursos scoped por `aws:ResourceTag/Project=spark-match` y ARN patterns con `*-dev` / `*-prod`.
3. **S3 backend**: bucket y key separados por env.
4. **GH Environment**: dev sin reviewers, production con reviewers + branch policy.
5. **Caller workflow**: cada job pasa el secret específico del env (`AWS_PLAN_ROLE_ARN_DEV` vs `AWS_PLAN_ROLE_ARN_PROD`).

**¿Por qué separar plan vs apply?** Si alguien mete código malicioso en un PR, solo puede **leer** tu infra, no destruirla.

**¿Por qué separar por env (4 roles)?** Si las credenciales OIDC de dev se filtran, el atacante puede tocar dev pero NO prod (el role de dev no tiene permisos para los recursos de prod).

> Nota: el caller `terraform-plan.yml` usa `-lock=false` porque el S3 lockfile de Terraform 1.6+ requiere `PutObject`, que es write. El plan es read-only por naturaleza, no necesita lock real.

### GitHub Secrets en este repo (estado actual)

```bash
# Listar
gh secret list --repo spark-match/spark-match-02-infrastructure

# Resultado:
# AWS_APPLY_ROLE_ARN          (legacy, no usado por callers actuales)
# AWS_APPLY_ROLE_ARN_DEV      arn:aws:iam::681526276858:role/spark-match-terraform-apply-dev
# AWS_APPLY_ROLE_ARN_PROD     arn:aws:iam::681526276858:role/spark-match-terraform-apply
# AWS_PLAN_ROLE_ARN           (legacy, no usado por callers actuales)
# AWS_PLAN_ROLE_ARN_DEV       arn:aws:iam::681526276858:role/spark-match-terraform-plan-dev
# AWS_PLAN_ROLE_ARN_PROD      arn:aws:iam::681526276858:role/spark-match-terraform-plan
```

Para un nuevo env (e.g. `staging`), agregar 2 secrets:
```bash
gh secret set AWS_PLAN_ROLE_ARN_STAGING  --body "arn:aws:iam::...:role/spark-match-terraform-plan-staging"
gh secret set AWS_APPLY_ROLE_ARN_STAGING --body "arn:aws:iam::...:role/spark-match-terraform-apply-staging"
```

### Setup OIDC (una vez)

#### Paso 1: Crear IAM Identity Provider

Solo se hace **una vez por cuenta AWS**:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

> El thumbprint es estable desde 2023. Si GitHub cambia su cert raíz, hay que actualizarlo.

#### Paso 2: Trust policy (compartida, multi-env)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::681526276858:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/main",
            "repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/dev",
            "repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/*",
            "repo:spark-match/spark-match-02-infrastructure:pull_request",
            "repo:spark-match/spark-match-02-infrastructure:environment:dev",
            "repo:spark-match/spark-match-02-infrastructure:environment:production"
          ]
        }
      }
    }
  ]
}
```

#### Pasos 3-5: crear roles, policies, secrets, environments

Ver el script original o ejecutar manualmente con `aws iam create-role`, `aws iam put-role-policy`, `gh secret set`, `gh api environments`.

#### Paso 6: Crear GitHub Environments

```bash
# Dev (sin reviewers)
gh api --method PUT "repos/spark-match/spark-match-02-infrastructure/environments/dev" \
  --input '{"wait_timer":0,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
gh api --method POST "repos/spark-match/spark-match-02-infrastructure/environments/dev/deployment-branch-policies" \
  --input '{"name":"dev"}'

# Production (con reviewers)
gh api --method PUT "repos/spark-match/spark-match-02-infrastructure/environments/production" \
  --input '{"wait_timer":0,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true},"reviewers":[{"type":"User","id":<github_user_id>}]}'
gh api --method POST "repos/spark-match/spark-match-02-infrastructure/environments/production/deployment-branch-policies" \
  --input '{"name":"main"}'
```

### Troubleshooting

| Error | Causa | Solución |
|---|---|---|
| `Credentials could not be loaded` | Secret no configurado o role no existe | Verifica `gh secret list` y `aws iam get-role` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy no incluye este repo/branch o falta el `sub` pattern del env | Agregar el patrón correspondiente al `sub` |
| `AccessDenied: s3:PutObject on terraform.tfstate.tflock` | Plan usando lock (no debería) | El caller usa `-lock=false` |
| `AccessDenied` en plan | Plan role no cubre alguna lectura | Agregar la acción específica a `plan-policy.json` |
| `AccessDenied` en apply | Apply role no cubre alguna acción | Agregar a `apply-policy.json` |
| Plan funciona local pero falla en CI | Falta secret `AWS_PLAN_ROLE_ARN` en repo | `gh secret set AWS_PLAN_ROLE_ARN ...` |

Verificar qué `sub` claim se está enviando:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-items 3 \
  --query 'Events[].User' \
  --output text
```

Debería verse:
```
repo:spark-match/spark-match-02-infrastructure:pull_request
repo:spark-match/spark-match-02-infrastructure:environment:dev
repo:spark-match/spark-match-02-infrastructure:environment:production
```

---

## Roadmap

| Fase | Contenido | Estado |
|---|---|---|
| **0** | Repo + `live/dev` y `live/prod` skeleton + reusable workflows + diseño de roles IAM + bootstrap de buckets | 🟢 Cerrada |
| **1** | `modules/security` (IAM base, KMS, SG) + `modules/networking` (VPC, subnets, NAT) + `modules/endpoints` (VPC interface endpoints) | 🟢 Escritos, sin apply |
| 1.5 | Componer `live/{dev,prod}/main.tf` con los 3 modulos + primer `terraform apply` | ⏳ Próxima |
| 2 | `modules/database` (Aurora + pgvector) + `modules/storage` (S3) + `modules/events` (EventBridge) + `modules/secrets` + `modules/monitoring` | ⏳ |
| 3 | Deploy de `03-backend` via `sam-deploy.yml` (TF crea los SSM params que SAM consume) | ⏳ |
| 4 | `modules/bedrock` + ECR + Dockerfile + `agentcore-deploy.yml` para `08-deep-agent` | ⏳ |
| 5 | Drift detection diario + Infracost en PRs + CODEOWNERS linter reusable | ⏳ |

---

## Licencia

MIT — ver [LICENSE](LICENSE).
