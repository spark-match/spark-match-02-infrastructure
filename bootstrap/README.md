# bootstrap/

Permisos del rol con el que **corre** Terraform, gestionados fuera de Terraform.

## Por que no son un modulo

Los 4 roles `spark-match-terraform-{plan,apply}-{dev,prod}` son los que GitHub
Actions asume para ejecutar `terraform plan` y `terraform apply`. Si Terraform
gestionara sus propias credenciales, un cambio malo lo dejaria sin permisos para
arreglarse a si mismo: el apply que instalaria la correccion es exactamente el
que ya no puede correr.

`docs/IAM_ROLES.md` los lista como *"Roles Terraform plan/apply (existentes, no
modificar)"*, y ningun `.tf` los declara. `modules/kms/main.tf` solo referencia
el ARN del rol de apply en la key policy.

## Que si cambia con esto

Hasta ahora el **contenido** de esos permisos no estaba versionado en ningun
lado: se habia aplicado a mano y nadie tenia forma de revisar ni de reproducir
el estado. Eso causo un fallo real que estuvo activo mucho tiempo (ver abajo).

Los documentos viven aca como JSON revisable, con `${environment}` interpolado
igual que hace `templatefile()` en `modules/oidc-github`. Se aplican con
`apply-bootstrap-policies.py`, que es idempotente.

Se adjuntan como **managed policies**, no editando el inline `ApplyPolicy` de 18
statements que ya existe. Es aditivo y se revierte con un `detach-role-policy`.

## El fallo que motiva esto

El `terraform apply` de dev llevaba tiempo siendo un no-op silencioso:

1. `terraform plan` fallaba con 14 `AccessDenied` durante el refresh, porque el
   rol no podia leer sus propios recursos (`ssm:GetParameter`,
   `secretsmanager:DescribeSecret`, `dynamodb:DescribeTable`,
   `sqs:GetQueueAttributes`, `rds:DescribeDBSubnetGroups`,
   `cloudfront:GetOriginAccessControl`, `s3:GetBucketOwnershipControls`,
   `sns:GetTopicAttributes`, `events:DescribeArchive`).
2. El plan salia con exit code 1.
3. `reusable-terraform-apply.yml` en 01-devops trataba cualquier exit distinto
   de 2 como "sin cambios", saltaba el apply y dejaba el job **en verde**.

Prueba: el trust policy de `spark-match-sam-deploy-dev` seguia teniendo el
patron `@*` que el PR #156 ya habia eliminado del codigo.

Dos causas de raiz, y las dos se arreglan por separado:

- Los permisos que faltan -> este directorio.
- El plan fallido que se reporta como exito -> arreglo en 01-devops.

Aparte, dos patrones del inline nunca matchearon nada real, porque piden un
`-dev` literal que los nombres no tienen:

| Patron del inline | Recurso real |
|---|---|
| `parameter/spark-match/*-dev*` | `/spark-match/dev/config/db-secret-arn` |
| `log-group:/aws/spark-match/*-dev*` | `/aws/spark-match/agent/dev/service` |

## Uso

```bash
# Ver que haria, sin tocar nada
python bootstrap/apply-bootstrap-policies.py dev

# Aplicar
python bootstrap/apply-bootstrap-policies.py dev --apply

# Revertir
aws iam detach-role-policy --profile spark-match-admin \
  --role-name spark-match-terraform-apply-dev \
  --policy-arn arn:aws:iam::681526276858:policy/spark-match-tf-apply-refresh-dev
```

Python y no PowerShell a proposito: `scripts/generate-policies.ps1` escribe los
JSON con BOM UTF-8 (`efbbbf`), que rompe cualquier parser de JSON. Los 4
archivos de `modules/oidc-github/policies/{dev,prod}/` lo tienen hoy. Ver
`AGENTS.md` seccion de gotchas de PowerShell.

## Follow-up

Traer los 4 roles a Terraform con `terraform import` en un
`modules/iam-terraform-roles`, si alguna vez se acepta el riesgo de auto-bloqueo
(o se deja un rol de rescate aparte). Esta fuera del alcance del despliegue
inicial.
