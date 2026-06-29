# Bootstrap log — OIDC setup

Fecha de configuración: 2026-06-29

## Recursos creados en AWS

### OIDC Identity Provider
- **ARN**: `arn:aws:iam::681526276858:oidc-provider/token.actions.githubusercontent.com`
- **URL**: `https://token.actions.githubusercontent.com`
- **Client ID**: `sts.amazonaws.com`
- **Thumbprint**: `6938fd4d98bab03faadb97b34396831e3780aea1`

### IAM Role
- **Nombre**: `spark-match-github-actions-terraform`
- **ARN**: `arn:aws:iam::681526276858:role/spark-match-github-actions-terraform`
- **Max session duration**: 3600 segundos (1 hora)
- **Trust policy**: `docs/oidc-setup/trust-policy.json`
- **Permissions policy**: `docs/oidc-setup/permissions-policy.json` (inline, nombre `TerraformPermissions`)

## GitHub Secrets

| Secret | Valor |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::681526276858:role/spark-match-github-actions-terraform` |

## Verificación

- [x] OIDC provider creado en IAM
- [x] Role creado y asumible por GitHub Actions
- [x] Permissions policy con permisos para S3 (state + POC) y EC2 (read-only)
- [x] Secret configurado en el repo `spark-match-02-infrastructure`

## Próximos pasos sugeridos

1. Crear PR de prueba → verificar que `terraform-plan.yml` asume el role correctamente
2. Crear workflow `terraform-apply.yml` con approval gate
3. Crear workflow `terraform-drift.yml` con cron diario
4. Separar roles: `AWS_PLAN_ROLE_ARN` (read-only) vs `AWS_APPLY_ROLE_ARN` (write)

## Referencias

- Documentación completa en [`docs/oidc-setup/README.md`](./README.md)
- AWS docs: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
- GitHub docs: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services