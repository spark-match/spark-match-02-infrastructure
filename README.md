# Spark Match -- Infraestructura como C\'odigo

Infraestructura AWS del proyecto **Spark Match** (Copiloto de Orientaci\'on Vocacional con IA Generativa), gestionada con **Terraform puro**.

> Repositorio: [spark-match/spark-match-02-infrastructure](https://github.com/spark-match/spark-match-02-infrastructure)
> Propietario: `@spark-match/devops`

---

## Stack

- **Cloud:** AWS (`us-east-1`)
- **IaC:** Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.40`
- **Backend:** S3 (state) + DynamoDB (locks)
- **Linting:** `tflint`, `terraform fmt`, `pre-commit-terraform`
- **CI/CD:** GitHub Actions con OIDC hacia AWS

## Estructura

```
spark-match-02-infrastructure/
|-- modules/                      # Modulos reutilizables de Terraform
|   |-- networking/               # VPC, subnets, NAT, IGW (Fase 1)
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
|       |-- main.tf               # Compone los modulos
|       |-- variables.tf
|       |-- outputs.tf
|       |-- versions.tf           # Required Terraform + providers
|       |-- providers.tf          # AWS provider
|       |-- terraform.tfvars.example
|-- scripts/
|   |-- bootstrap-backend.sh      # Crea S3 + DynamoDB (ejecutar 1 vez)
|   |-- plan.sh                   # terraform plan
|   |-- apply.sh                  # terraform apply
|   |-- destroy.sh                # terraform destroy (con confirmacion)
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

Antes del primer `terraform init`, crear el bucket S3 y la tabla DynamoDB para el state remoto:

```bash
chmod +x scripts/*.sh
./scripts/bootstrap-backend.sh
```

Esto crea:
- S3 bucket `spark-match-tfstate-prod` con versionado y encriptaci\'on
- DynamoDB table `spark-match-tflock` para lock

## Uso diario

```bash
cd live/prod
terraform init -backend-config="bucket=spark-match-tfstate-prod" \
               -backend-config="key=prod/terraform.tfstate" \
               -backend-config="region=us-east-1" \
               -backend-config="dynamodb_table=spark-match-tflock"

cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars seg\'un necesidad

./scripts/plan.sh prod
./scripts/apply.sh prod
```

## Workflow de desarrollo

1. Crear rama: `git checkout -b feat/<modulo>-<descripcion>`
2. Editar o agregar modulos en `modules/`
3. Consumir desde `live/prod/main.tf`
4. Abrir PR hacia `main` -- el workflow `terraform-plan.yml` corre `fmt + validate + plan`
5. CODEOWNERS requiere aprobaci\'on de `@spark-match/devops` o `@spark-match/product-owners`
6. Al mergear, el state se actualiza pero **NO** se aplica autom\'aticamente (requiere aprobaci\'on manual via workflow `terraform-apply` cuando se implemente)

## A\'nadir un nuevo m\'odulo

1. `mkdir -p modules/<nombre>`
2. Crear `main.tf`, `variables.tf`, `outputs.tf`, `README.md`
3. Agregar un bloque `module "<nombre>"` en `live/prod/main.tf`
4. (Opcional) agregar variables en `live/prod/variables.tf` y defaults en `terraform.tfvars.example`

## Roles AWS necesarios para CI

El workflow de GitHub Actions usa **OIDC** (sin access keys de larga duraci\'on). Se necesita:

- Un IAM Role con `信任` policy para el repo `spark-match/spark-match-02-infrastructure`
- Permisos de lectura/escritura sobre los servicios que Terraform gestiona
- ARN guardado como secret `AWS_DEPLOY_ROLE_ARN`

## Roadmap

| Fase | Contenido |
|---|---|
| **1 (actual)** | Repo + `modules/networking` + `live/prod` + CI plan |
| 2 | `modules/database` (RDS) + `modules/storage` (S3) |
| 3 | `modules/compute` (ECS Fargate) + `modules/cdn` (CloudFront) |
| 4 | `modules/security`, `secrets`, `monitoring`, `bedrock` (IAM) |
| 5 | Workflow `terraform-apply` con environment protection rule |

## Licencia

MIT -- ver [LICENSE](LICENSE).