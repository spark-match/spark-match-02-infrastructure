# Configuración de OIDC para GitHub Actions → AWS

Esta guía explica cómo configurar **OpenID Connect (OIDC)** para que GitHub Actions pueda asumir roles IAM en AWS sin necesidad de access keys de larga duración.

## ¿Por qué OIDC?

| Método | Seguridad | Rotación | Secretos en GitHub |
|---|---|---|---|
| Access keys | Baja (filtrables) | Manual | 2 (key + secret) |
| **OIDC** | Alta (sts:AssumeRoleWithWebIdentity) | Automática (1h) | 1 (ARN por role) |

## Arquitectura

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

## Estrategia de roles separados (recomendado)

Para minimizar el blast radius, usamos **dos roles** con permisos mínimos:

| Role | Uso | Permisos | Secret en GitHub |
|---|---|---|---|
| `spark-match-terraform-plan` | `terraform plan` en PRs | **Read-only** (S3 Get/List, EC2 Describe, IAM Get) | `AWS_PLAN_ROLE_ARN` |
| `spark-match-terraform-apply` | `terraform apply` en merges | **Write** (todo lo de plan + S3/EC2/IAM Put/Create/Delete) | `AWS_APPLY_ROLE_ARN` |

**¿Por qué separar?** Si alguien mete código malicioso en un PR, solo puede **leer** tu infra, no destruirla.

> Nota: el workflow `terraform-plan.yml` usa `-lock=false` porque el S3 lockfile de Terraform 1.6+ requiere `PutObject`, que es write. El plan es read-only por naturaleza, no necesita lock real.

## Pre-requisitos

- Cuenta AWS con permisos de IAM admin
- Repo `spark-match-02-infrastructure` en GitHub
- AWS CLI configurado con perfil admin

---

## Paso 1: Crear IAM Identity Provider

Solo se hace **una vez por cuenta AWS**.

### Opción A: AWS Console

IAM → Identity providers → Add provider:
- Provider type: `OpenID Connect`
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- Click "Get thumbprint" → Add

### Opción B: AWS CLI

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

> El thumbprint es estable desde 2023. Si GitHub cambia su cert raíz, hay que actualizarlo.

---

## Paso 2: Crear los IAM Roles (plan + apply)

Necesitamos **3 documentos JSON**:
- `trust-policy.json` — quién puede asumir el role (compartido)
- `plan-policy.json` — permisos del role de plan (read-only)
- `apply-policy.json` — permisos del role de apply (write)

### 2a. Trust policy (ya incluido en `trust-policy.json`)

Compartido entre ambos roles. Permite:
- ✅ Pushes a `main`
- ✅ Cualquier PR branch
- ✅ Workflows con environment `production`

### 2b. Plan policy (ya incluido en `plan-policy.json`)

Permisos read-only:
- `s3:Get*`, `s3:List*` en buckets del proyecto
- `ec2:Describe*` para refrescar el estado
- `sts:GetCallerIdentity` (requerido por el SDK)

### 2c. Apply policy (ya incluido en `apply-policy.json`)

Permisos completos:
- Todo lo de plan, MÁS:
- `s3:CreateBucket`, `s3:PutBucket*`, `s3:DeleteBucket`
- `ec2:Create*`, `ec2:Modify*`, `ec2:Delete*`
- `iam:PassRole` (para EC2 instance profiles, ECS task roles, etc.)

### 2d. Crear los roles

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

---

## Paso 3: Agregar los ARNs como GitHub Secrets

### Opción A: GitHub Web

https://github.com/spark-match/spark-match-02-infrastructure/settings/secrets/actions

| Secret | Valor |
|---|---|
| `AWS_PLAN_ROLE_ARN` | ARN del role de plan |
| `AWS_APPLY_ROLE_ARN` | ARN del role de apply |

### Opción B: gh CLI

```bash
gh secret set AWS_PLAN_ROLE_ARN \
  --repo spark-match/spark-match-02-infrastructure \
  --body "$PLAN_ARN"

gh secret set AWS_APPLY_ROLE_ARN \
  --repo spark-match/spark-match-02-infrastructure \
  --body "$APPLY_ARN"
```

---

## Paso 4: Configurar los workflows

### terraform-plan.yml (PR)

```yaml
- name: Configure AWS credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v5
  with:
    role-to-assume: ${{ secrets.AWS_PLAN_ROLE_ARN }}   # <-- plan role
    aws-region: us-east-1
```

Y usar `-lock=false` en el plan:

```yaml
- name: Terraform plan
  run: terraform plan -input=false -no-color -lock=false -out=tfplan
```

### terraform-apply.yml (merge, cuando se implemente)

```yaml
- name: Configure AWS credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v5
  with:
    role-to-assume: ${{ secrets.AWS_APPLY_ROLE_ARN }}   # <-- apply role
    aws-region: us-east-1

- name: Terraform apply
  run: terraform apply -input=false tfplan
```

---

## Paso 5: Probar

### Probar plan role

```bash
# Crear PR de prueba
git checkout -b test/oidc-plan
# (modificar cualquier archivo .tf o .tfvars)
git push -u origin test/oidc-plan
gh pr create --fill
```

El workflow `terraform-plan.yml` debería pasar.

### Probar apply role

Por ahora el workflow `terraform-apply.yml` no existe. Cuando se implemente (Fase 5 del roadmap), se prueba con un merge a `main`.

---

## Expansión futura

Cuando agregues más módulos, expande `apply-policy.json`:

| Módulo | Permisos a agregar (apply) |
|---|---|
| `database` (RDS) | `rds:*` en recursos específicos |
| `compute` (ECS Fargate) | `ecs:*`, más `iam:PassRole` |
| `cdn` (CloudFront) | `cloudfront:*`, `acm:ListCertificates` |
| `security` (IAM roles) | `iam:CreateRole`, `iam:AttachRolePolicy` |
| `secrets` (Secrets Manager) | `secretsmanager:*` |
| `monitoring` (CloudWatch) | `logs:*`, `cloudwatch:*` |
| `bedrock` | `bedrock:*` |

Mantén el principio de **least privilege**: cada acción solo sobre los recursos del proyecto `spark-match-*`.

**Para el plan role, NO necesitas expandir casi nada** — solo `Describe*` de los nuevos servicios para refrescar el estado.

---

## Troubleshooting

| Error | Causa | Solución |
|---|---|---|
| `Credentials could not be loaded` | Secret no configurado o role no existe | Verifica `gh secret list` y `aws iam get-role` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy no incluye este repo/branch o no incluye `pull_request` pattern | Ajusta el `sub` pattern (ver `trust-policy.json`) |
| `AccessDenied: s3:PutObject on terraform.tfstate.tflock` | Plan usando lock (no debería) | Usa `-lock=false` en el plan |
| `AccessDenied` en plan | Plan role no cubre alguna lectura | Agrega la acción específica a `plan-policy.json` |
| `AccessDenied` en apply | Apply role no cubre alguna acción | Agrega a `apply-policy.json` |
| `Token expired` | Normal, dura 1h | El workflow ya maneja esto |

## CloudTrail para debugging

Para ver qué `sub` claim se está enviando:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-items 3 \
  --query 'Events[].User' \
  --output text
```

Debería verse algo como:
```
repo:spark-match/spark-match-02-infrastructure:pull_request
repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/main
```

---

## Comandos todo-en-uno

```bash
# Asume que ya estás en D:\UNI\Spark\02-infrastructure\docs\oidc-setup\

# 1. Crear OIDC provider (si no existe)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2. Crear roles
aws iam create-role \
  --role-name spark-match-terraform-plan \
  --assume-role-policy-document file://trust-policy.json
aws iam put-role-policy \
  --role-name spark-match-terraform-plan \
  --policy-name PlanPolicy \
  --policy-document file://plan-policy.json

aws iam create-role \
  --role-name spark-match-terraform-apply \
  --assume-role-policy-document file://trust-policy.json
aws iam put-role-policy \
  --role-name spark-match-terraform-apply \
  --policy-name ApplyPolicy \
  --policy-document file://apply-policy.json

# 3. Setear secrets en GitHub
PLAN_ARN=$(aws iam get-role --role-name spark-match-terraform-plan --query 'Role.Arn' --output text)
APPLY_ARN=$(aws iam get-role --role-name spark-match-terraform-apply --query 'Role.Arn' --output text)

gh secret set AWS_PLAN_ROLE_ARN  --repo spark-match/spark-match-02-infrastructure --body "$PLAN_ARN"
gh secret set AWS_APPLY_ROLE_ARN --repo spark-match/spark-match-02-infrastructure --body "$APPLY_ARN"
```