# Spark Match — Infraestructura como Código

Infraestructura AWS del proyecto **Spark Match** (Copiloto de Orientación Vocacional con IA Generativa), gestionada con **Terraform puro**.

> Repositorio: [spark-match/spark-match-02-infrastructure](https://github.com/spark-match/spark-match-02-infrastructure)
> Propietario: `@spark-match/devops`

---

## Stack

- **Cloud:** AWS (`us-east-1`)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 (state) + S3 native lockfile (sin DynamoDB)
- **Linting:** `tflint`, `terraform fmt`, `pre-commit-terraform`
- **CI/CD:** GitHub Actions con **OIDC** hacia AWS (roles separados plan/apply)
- **Pipelines:** [Reusable workflows](https://github.com/spark-match/spark-match-01-devops) desde `spark-match-01-devops`

## Estructura

```
spark-match-02-infrastructure/
|-- modules/                      # Módulos reutilizables de Terraform
|   |-- networking/               # VPC, subnets, NAT, IGW (Fase 1, no aplicado)
|   |-- s3-example/               # Bucket S3 de ejemplo (Fase 1, prueba de concepto)
|   |-- database/                 # RDS PostgreSQL (Fase 2)
|   |-- storage/                  # S3 buckets (Fase 2)
|   |-- compute/                  # ECS Fargate (Fase 3)
|   |-- cdn/                      # CloudFront (Fase 3)
|   |-- security/                 # IAM roles, security groups (Fase 4)
|   |-- secrets/                  # Secrets Manager (Fase 4)
|   |-- monitoring/               # CloudWatch + SNS (Fase 4)
|   |-- bedrock/                  # IAM para AWS Bedrock (Fase 4)
|-- live/
|   |-- prod/                     # Instancia productiva
|       |-- main.tf               # Compone los módulos
|       |-- variables.tf
|       |-- outputs.tf
|       |-- versions.tf           # Required Terraform + providers + backend s3
|       |-- providers.tf          # AWS provider + default_tags
|       |-- terraform.tfvars.example
|-- scripts/
|   |-- bootstrap-backend.sh      # Crea S3 bucket (ejecutar 1 vez)
|   |-- plan.sh                   # terraform plan
|   |-- apply.sh                  # terraform apply
|   |-- destroy.sh                # terraform destroy (con confirmación)
|-- .github/workflows/
|   |-- terraform-plan.yml        # Caller de reusable workflow (PR)
|   |-- terraform-apply.yml       # Caller de reusable workflow (merge, con approval)
|-- .tflint.hcl
|-- .pre-commit-config.yaml
|-- LICENSE
|-- README.md
```

## Pre-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.6.0`
- [AWS CLI](https://aws.amazon.com/cli/) configurado con un perfil o variables de entorno
- (Opcional) [pre-commit](https://pre-commit.com/) + [tflint](https://github.com/terraform-linters/tflint)

---

## Bootstrap (primera vez)

Antes del primer `terraform init`, crear el bucket S3 para el state remoto:

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-backend.sh
```

Esto crea el bucket S3 `spark-match-tfstate-prod` con versionado y encriptación. El locking se hace con **S3 native lockfile** (no requiere DynamoDB desde Terraform 1.6).

### Verificar el bucket manualmente

```bash
aws --profile spark-match-prod --region us-east-1 s3api get-bucket-versioning \
  --bucket spark-match-tfstate-prod

aws --profile spark-match-prod --region us-east-1 s3api get-bucket-encryption \
  --bucket spark-match-tfstate-prod
```

---

## Uso diario

### Terraform local

```bash
cd live/prod
terraform init -backend-config="bucket=spark-match-tfstate-prod" \
               -backend-config="key=prod/terraform.tfstate" \
               -backend-config="region=us-east-1" \
               -backend-config="use_lockfile=true"

cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars según necesidad

./scripts/plan.sh prod
./scripts/apply.sh prod
```

### Con variables de entorno PowerShell (Windows)

```powershell
$env:AWS_PROFILE="spark-match-prod"
$env:AWS_REGION="us-east-1"
$env:AWS_SDK_LOAD_CONFIG="1"   # Necesario para que Terraform lea el perfil

terraform init -backend-config="bucket=spark-match-tfstate-prod" `
               -backend-config="key=prod/terraform.tfstate" `
               -backend-config="region=us-east-1" `
               -backend-config="use_lockfile=true"

terraform plan
```

---

## Workflow de desarrollo

1. Crear rama: `git checkout -b feat/<modulo>-<descripcion>`
2. Editar o agregar módulos en `modules/`
3. Consumir desde `live/prod/main.tf`
4. Abrir PR hacia `main` → el workflow `terraform-plan.yml` corre (vía caller + reusable workflow)
5. CODEOWNERS requiere aprobación de `@spark-match/devops` o `@spark-match/product-owners`
6. Al mergear, el workflow `terraform-apply.yml` se triggerea con approval gate (environment `production`)
7. Aprobar el deployment en GitHub UI → `terraform apply` corre

---

## Añadir un nuevo módulo

1. `mkdir -p modules/<nombre>`
2. Crear `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
3. Agregar un bloque `module "<nombre>"` en `live/prod/main.tf`
4. (Opcional) agregar variables en `live/prod/variables.tf` y defaults en `terraform.tfvars.example`

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

### Estrategia de roles separados (recomendado)

Para minimizar el blast radius, usamos **dos roles** con permisos mínimos:

| Role | ARN | Permisos | Secret en GitHub |
|---|---|---|---|
| `spark-match-terraform-plan` | `arn:aws:iam::681526276858:role/spark-match-terraform-plan` | **Read-only** (S3 Get/List, EC2 Describe, IAM Get) | `AWS_PLAN_ROLE_ARN` |
| `spark-match-terraform-apply` | `arn:aws:iam::681526276858:role/spark-match-terraform-apply` | **Write** (todo lo de plan + S3/EC2/IAM Put/Create/Delete) | `AWS_APPLY_ROLE_ARN` |

**¿Por qué separar?** Si alguien mete código malicioso en un PR, solo puede **leer** tu infra, no destruirla.

> Nota: el caller `terraform-plan.yml` usa `-lock=false` porque el S3 lockfile de Terraform 1.6+ requiere `PutObject`, que es write. El plan es read-only por naturaleza, no necesita lock real.

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

#### Paso 2: Trust policy (compartida)

Crea un archivo `trust-policy.json`:

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
            "repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/*",
            "repo:spark-match/spark-match-02-infrastructure:pull_request",
            "repo:spark-match/spark-match-02-infrastructure:environment:production"
          ]
        }
      }
    }
  ]
}
```

#### Paso 3: Plan policy (read-only)

Crea un archivo `plan-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ReadForStateRefresh",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:ListBucketVersions"
      ],
      "Resource": [
        "arn:aws:s3:::spark-match-tfstate-prod",
        "arn:aws:s3:::spark-match-tfstate-prod/*"
      ]
    },
    {
      "Sid": "S3ReadForBucketDiscovery",
      "Effect": "Allow",
      "Action": [
        "s3:GetAccelerateConfiguration",
        "s3:GetBucketAcl",
        "s3:GetBucketCORS",
        "s3:GetBucketEncryption",
        "s3:GetBucketLogging",
        "s3:GetBucketNotification",
        "s3:GetBucketObjectLockConfiguration",
        "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketRequestPayment",
        "s3:GetBucketTagging",
        "s3:GetBucketVersioning",
        "s3:GetBucketWebsite",
        "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration"
      ],
      "Resource": [
        "arn:aws:s3:::spark-match-poc-*",
        "arn:aws:s3:::spark-match-tfstate-*"
      ]
    },
    {
      "Sid": "EC2ReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeRouteTables",
        "ec2:DescribeRouteTableAssociations",
        "ec2:DescribeNatGateways",
        "ec2:DescribeNetworkAcls",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

#### Paso 4: Apply policy (write)

Crea un archivo `apply-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3StateManagement",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning"
      ],
      "Resource": [
        "arn:aws:s3:::spark-match-tfstate-prod",
        "arn:aws:s3:::spark-match-tfstate-prod/*"
      ]
    },
    {
      "Sid": "S3BucketManagement",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketEncryption",
        "s3:PutBucketTagging",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:PutLifecycleConfiguration",
        "... (todas las acciones S3 necesarias)"
      ],
      "Resource": [
        "arn:aws:s3:::spark-match-poc-*",
        "arn:aws:s3:::spark-match-tfstate-*"
      ]
    },
    {
      "Sid": "EC2FullManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway",
        "ec2:CreateRouteTable",
        "ec2:AssociateRouteTable",
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "... (todas las acciones EC2 necesarias)"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

#### Paso 5: Crear los roles

```bash
# Role de PLAN (read-only)
aws iam create-role \
  --role-name spark-match-terraform-plan \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role para terraform plan (read-only)" \
  --max-session-duration 3600

aws iam put-role-policy \
  --role-name spark-match-terraform-plan \
  --policy-name PlanPolicy \
  --policy-document file://plan-policy.json

# Role de APPLY (write)
aws iam create-role \
  --role-name spark-match-terraform-apply \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role para terraform apply (write)" \
  --max-session-duration 3600

aws iam put-role-policy \
  --role-name spark-match-terraform-apply \
  --policy-name ApplyPolicy \
  --policy-document file://apply-policy.json

# Obtener los ARNs
PLAN_ARN=$(aws iam get-role --role-name spark-match-terraform-plan --query 'Role.Arn' --output text)
APPLY_ARN=$(aws iam get-role --role-name spark-match-terraform-apply --query 'Role.Arn' --output text)
echo "Plan:   $PLAN_ARN"
echo "Apply:  $APPLY_ARN"
```

#### Paso 6: Agregar los ARNs como GitHub Secrets

```bash
gh secret set AWS_PLAN_ROLE_ARN  --repo spark-match/spark-match-02-infrastructure --body "$PLAN_ARN"
gh secret set AWS_APPLY_ROLE_ARN --repo spark-match/spark-match-02-infrastructure --body "$APPLY_ARN"
```

#### Paso 7: Configurar GitHub Environment `production`

Para que `terraform-apply.yml` requiera aprobación manual:

```bash
gh api -X PUT repos/spark-match/spark-match-02-infrastructure/environments/production \
  -H "Accept: application/vnd.github+json" --input environment.json
```

Donde `environment.json`:

```json
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [{"type": "User", "id": <your_github_user_id>}],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
```

Y luego:

```bash
gh api -X POST repos/spark-match/spark-match-02-infrastructure/environments/production/deployment-branch-policies \
  -H "Accept: application/vnd.github+json" --input '{"name":"main"}'
```

### Troubleshooting

| Error | Causa | Solución |
|---|---|---|
| `Credentials could not be loaded` | Secret no configurado o role no existe | Verifica `gh secret list` y `aws iam get-role` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy no incluye este repo/branch o falta `pull_request` pattern | Agregar el patrón correspondiente al `sub` |
| `AccessDenied: s3:PutObject on terraform.tfstate.tflock` | Plan usando lock (no debería) | El caller usa `-lock=false` |
| `AccessDenied` en plan | Plan role no cubre alguna lectura | Agregar la acción específica a `plan-policy.json` |
| `AccessDenied` en apply | Apply role no cubre alguna acción | Agregar a `apply-policy.json` |

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
repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/main
```

---

## Roadmap

| Fase | Contenido |
|---|---|
| **1 (actual)** | Repo + `modules/networking` + `modules/s3-example` + `live/prod` + CI/CD via reusable workflows |
| 2 | `modules/database` (RDS) + `modules/storage` (S3) |
| 3 | `modules/compute` (ECS Fargate) + `modules/cdn` (CloudFront) |
| 4 | `modules/security`, `secrets`, `monitoring`, `bedrock` (IAM) |
| 5 | Drift detection diario + Infracost en PRs |

---

## Licencia

MIT — ver [LICENSE](LICENSE).