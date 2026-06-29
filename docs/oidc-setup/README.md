# Configuración de OIDC para GitHub Actions → AWS

Esta guía explica cómo configurar **OpenID Connect (OIDC)** para que GitHub Actions pueda asumir un rol IAM en AWS sin necesidad de access keys de larga duración.

## ¿Por qué OIDC?

| Método | Seguridad | Rotación | Secretos en GitHub |
|---|---|---|---|
| Access keys | Baja (filtrables) | Manual | 2 (key + secret) |
| **OIDC** | Alta (sts:AssumeRoleWithWebIdentity) | Automática (1h) | 1 (solo el ARN) |

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

## Paso 2: Crear el IAM Role

Necesita dos documentos:
- `trust-policy.json` — quién puede asumir el role
- `permissions-policy.json` — qué puede hacer

### 2a. Trust policy (ya incluido en `trust-policy.json`)

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
            "repo:spark-match/spark-match-02-infrastructure:environment:production"
          ]
        }
      }
    }
  ]
}
```

**Scope que permite:**
- ✅ Pushes a `main`
- ✅ Cualquier PR branch (cualquier feature branch)
- ✅ Workflows con environment `production`

### 2b. Permissions policy (ya incluido en `permissions-policy.json`)

Esta policy cubre:
- **S3 bucket management** para buckets `spark-match-poc-*` y `spark-match-tfstate-*`
- **EC2 read-only** (Describe*) — necesario para que Terraform lea el estado actual
- **Terraform state access** (Get/Put/Delete objects en el bucket de state)

> Para Fase 2+ (RDS, ECS, etc.) hay que expandir esta policy.

### 2c. Crear el role

```bash
# Crear el role
aws iam create-role \
  --role-name spark-match-github-actions-terraform \
  --assume-role-policy-document file://trust-policy.json \
  --description "Role para GitHub Actions de Terraform (spark-match)" \
  --max-session-duration 3600

# Adjuntar la policy de permisos
aws iam put-role-policy \
  --role-name spark-match-github-actions-terraform \
  --policy-name TerraformPermissions \
  --policy-document file://permissions-policy.json

# Obtener el ARN
aws iam get-role --role-name spark-match-github-actions-terraform \
  --query 'Role.Arn' --output text
# → arn:aws:iam::681526276858:role/spark-match-github-actions-terraform
```

---

## Paso 3: Agregar el ARN como GitHub Secret

### Opción A: GitHub Web

https://github.com/spark-match/spark-match-02-infrastructure/settings/secrets/actions

- New repository secret
- Name: `AWS_DEPLOY_ROLE_ARN`
- Value: `arn:aws:iam::681526276858:role/spark-match-github-actions-terraform`

### Opción B: gh CLI

```bash
gh secret set AWS_DEPLOY_ROLE_ARN \
  --repo spark-match/spark-match-02-infrastructure \
  --body "arn:aws:iam::681526276858:role/spark-match-github-actions-terraform"
```

---

## Paso 4: Verificar el workflow

El archivo `.github/workflows/terraform-plan.yml` debe tener:

```yaml
- name: Configure AWS credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v5
  with:
    role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
    aws-region: us-east-1
    audience: sts.amazonaws.com
```

---

## Paso 5: Probar

Crear un PR nuevo en el repo. El workflow `terraform-plan.yml` debería:
1. ✅ Asumir el role correctamente
2. ✅ Ejecutar `terraform init`
3. ✅ Ejecutar `terraform plan`
4. ✅ Postear el plan como comentario del PR

Si falla, revisa:
- El ARN del role es correcto en el secret
- El repo name en la trust policy coincide con el repo real
- El identity provider existe en IAM

---

## Comandos todo-en-uno

```bash
# Asume que ya estás en D:\UNI\Spark\02-infrastructure\docs\oidc-setup\

# 1. Crear OIDC provider (si no existe)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2. Crear role + adjuntar permisos
aws iam create-role \
  --role-name spark-match-github-actions-terraform \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name spark-match-github-actions-terraform \
  --policy-name TerraformPermissions \
  --policy-document file://permissions-policy.json

# 3. Setear el secret en GitHub
gh secret set AWS_DEPLOY_ROLE_ARN \
  --repo spark-match/spark-match-02-infrastructure \
  --body "$(aws iam get-role --role-name spark-match-github-actions-terraform --query 'Role.Arn' --output text)"
```

---

## Expansión futura

Cuando agregues más módulos, expande `permissions-policy.json`:

| Módulo | Permisos a agregar |
|---|---|
| `database` (RDS) | `rds:*` en recursos específicos |
| `compute` (ECS Fargate) | `ecs:*`, `iam:PassRole` |
| `cdn` (CloudFront) | `cloudfront:*`, `acm:ListCertificates` |
| `security` (IAM roles) | `iam:CreateRole`, `iam:AttachRolePolicy` |
| `secrets` (Secrets Manager) | `secretsmanager:*` |
| `monitoring` (CloudWatch) | `logs:*`, `cloudwatch:*` |
| `bedrock` | `bedrock:*`, `iam:PassRole` |

Mantén el principio de **least privilege**: cada acción solo sobre los recursos del proyecto `spark-match-*`.

---

## Troubleshooting

| Error | Causa | Solución |
|---|---|---|
| `Credentials could not be loaded` | Secret no configurado o role no existe | Verifica `gh secret list` y `aws iam get-role` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy no incluye este repo/branch | Ajusta el `sub` pattern |
| `AccessDenied` en plan | Permissions policy no cubre la acción | Agrega la acción específica |
| `Token expired` | Normal, dura 1h | El workflow ya maneja esto |