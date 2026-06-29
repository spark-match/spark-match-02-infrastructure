# Spark Match -- Infraestructura como Código

Infraestructura AWS del proyecto **Spark Match** (Copiloto de Orientación Vocacional con IA Generativa), gestionada con **Terraform puro**.

> Repositorio: [spark-match/spark-match-02-infrastructure](https://github.com/spark-match/spark-match-02-infrastructure)
> Propietario: `@spark-match/devops`

---

## Stack

- **Cloud:** AWS (`us-east-1`)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 (state) + S3 native lockfile (sin DynamoDB)
- **Linting:** `tflint`, `terraform fmt`, `pre-commit-terraform`
- **CI/CD:** GitHub Actions con OIDC hacia AWS

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
|       |-- versions.tf           # Required Terraform + providers
|       |-- providers.tf          # AWS provider
|       |-- terraform.tfvars.example
|-- scripts/
|   |-- bootstrap-backend.sh      # Crea S3 + (opcional) DynamoDB, ejecutar 1 vez
|   |-- plan.sh                   # terraform plan
|   |-- apply.sh                  # terraform apply
|   |-- destroy.sh                # terraform destroy (con confirmación)
|-- .github/workflows/
|   |-- terraform-plan.yml        # CI: plan en cada PR
|-- .tflint.hcl
|-- .pre-commit-config.yaml
|-- README.md
```

## Pre-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.6.0`
- [AWS CLI](https://aws.amazon.com/cli/) configurado con un perfil o variables de entorno
- (Opcional) [pre-commit](https://pre-commit.com/) + [tflint](https://github.com/terraform-linters/tflint)

## Bootstrap (primera vez)

Antes del primer `terraform init`, crear el bucket S3 para el state remoto:

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-backend.sh
```

Esto crea el bucket S3 `spark-match-tfstate-prod` con versionado y encriptación. El locking se hace con S3 native lockfile (no requiere DynamoDB desde Terraform 1.6).

## Uso diario

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

## Workflow de desarrollo

1. Crear rama: `git checkout -b feat/<modulo>-<descripcion>`
2. Editar o agregar módulos en `modules/`
3. Consumir desde `live/prod/main.tf`
4. Abrir PR hacia `main` -- el workflow `terraform-plan.yml` corre `fmt + validate + plan`
5. CODEOWNERS requiere aprobación de `@spark-match/devops` o `@spark-match/product-owners`
6. Al mergear, el state se actualiza pero **NO** se aplica automáticamente (requiere aprobación manual vía workflow `terraform-apply` cuando se implemente)

## Añadir un nuevo módulo

1. `mkdir -p modules/<nombre>`
2. Crear `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
3. Agregar un bloque `module "<nombre>"` en `live/prod/main.tf`
4. (Opcional) agregar variables en `live/prod/variables.tf` y defaults en `terraform.tfvars.example`

## Roles AWS necesarios para CI

El workflow de GitHub Actions usa **OIDC** (sin access keys de larga duración). Se necesita:

- Un IAM Role con trust policy para el repo `spark-match/spark-match-02-infrastructure`
- Permisos de lectura/escritura sobre los servicios que Terraform gestiona
- ARN guardado como secret `AWS_DEPLOY_ROLE_ARN`

## Roadmap

| Fase | Contenido |
|---|---|
| **1 (actual)** | Repo + `modules/networking` + `modules/s3-example` + `live/prod` + CI plan |
| 2 | `modules/database` (RDS) + `modules/storage` (S3) |
| 3 | `modules/compute` (ECS Fargate) + `modules/cdn` (CloudFront) |
| 4 | `modules/security`, `secrets`, `monitoring`, `bedrock` (IAM) |
| 5 | Workflow `terraform-apply` con environment protection rule |

## Licencia

MIT -- ver [LICENSE](LICENSE).