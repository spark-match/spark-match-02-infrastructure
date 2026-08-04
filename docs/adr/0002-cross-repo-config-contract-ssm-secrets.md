# ADR 0002 — Cross-repo config contract via SSM Parameter Store y Secrets Manager

> **Status**: accepted (amended 2026-08-04: +2 parametros SSM para VPC config de Lambda)
> **Date**: 2026-08-04
> **Deciders**: @ahincho

## Context

`spark-match-03-backend` despliega con AWS SAM y necesita, en tiempo de
`sam deploy` (deploy-time) y en runtime de las Lambdas, varios valores que
solo existen despues de que Terraform los crea en este repo:

- ARN del bus de EventBridge (`spark-match-events-{env}`)
- ARN del secret con credenciales de RDS (host/port/database/username/password)
- ARN del secret JWT (HS256 signing key)
- Connection URL completa de Postgres (solo para la Lambda `migrate`)
- Nombre de la tabla DynamoDB de idempotencia
- Lista de origenes CORS permitidos
- IDs de subnets privadas y security group de Lambda (VpcConfig — ver seccion 5)

Hasta este ADR, **ninguno de estos recursos existia**: `live/dev/outputs.tf`
y `live/prod/outputs.tf` estaban vacios (solo comentarios), no habia ni un
solo `aws_ssm_parameter` ni `aws_secretsmanager_secret` en todo el repo, y
la cuenta AWS (`681526276858`) estaba greenfield salvo el bootstrap OIDC +
buckets de tfstate (verificado con `aws ssm describe-parameters`,
`aws secretsmanager list-secrets`, `aws rds describe-db-instances`: todos
vacios).

El codigo de `03-backend` (`template.yaml`, `contexts/identity/template.yaml`)
ya referenciaba paths **sin ambiente**:

```
{{resolve:ssm:/spark-match/eventbridge/bus-arn}}
{{resolve:ssm:/spark-match/db/secret-arn}}
{{resolve:ssm:/spark-match/secret/jwt-arn}}
```

Como `dev` y `prod` comparten la **misma cuenta AWS**, estos paths sin
ambiente harian que `prod` leyera el secret/bus de `dev` (o viceversa,
segun orden de deploy). Esto es un riesgo de aislamiento real, no teorico.

## Decision

### 1. Paths SSM env-scoped

Todos los parametros SSM viven bajo:

```
/spark-match/{env}/config/{key}
```

Los 8 parametros concretos:

| Path | Tipo | Contenido |
|---|---|---|
| `/spark-match/{env}/config/eventbridge-bus-arn` | String | ARN del bus (identificador, no secreto) |
| `/spark-match/{env}/config/db-secret-arn` | String | ARN del secret de credenciales RDS (identificador) |
| `/spark-match/{env}/config/jwt-secret-arn` | String | ARN del secret JWT (identificador) |
| `/spark-match/{env}/config/db-connection-url` | **SecureString** | Postgres URL con password embebido — SI es secreto |
| `/spark-match/{env}/config/idempotency-table` | String | Nombre de tabla DynamoDB (identificador) |
| `/spark-match/{env}/config/cors-allowed-origins` | String | Lista de origenes, `*` en dev |
| `/spark-match/{env}/config/private-subnet-ids` | String | IDs de subnets privadas, CSV (identificador) |
| `/spark-match/{env}/config/lambda-security-group-id` | String | ID del SG de Lambda (identificador) |

Regla: **un ARN es un identificador, no un secreto** (mismo principio que
ya aplicamos a `vars.AWS_APPLY_ROLE_ARN` en GitHub Actions — ver AGENTS.md).
Solo `db-connection-url` contiene un password embebido y por eso es
`SecureString` cifrado con la CMK de `modules/kms`. Los IDs de red
(`private-subnet-ids`, `lambda-security-group-id`) son igual de publicos
que un ARN: identifican un recurso, no autorizan nada por si mismos (el
control de acceso real vive en IAM/security groups, no en el secreto de
conocer el ID).

### 2. Secrets Manager: naming y ownership

| Secret | Owner (modulo) | Contenido |
|---|---|---|
| `spark-match-{env}-db-credentials` | `modules/rds-postgres` | JSON `{host, port, database, username, password}` |
| `spark-match-{env}-jwt-secret` | `modules/secrets-bootstrap` | String aleatorio (48 bytes base64, equivalente a `openssl rand -base64 48`) |

`db-credentials` vive **dentro** del modulo `rds-postgres` (no en un modulo
`secrets-bootstrap` generico) porque necesita el endpoint/puerto/db-name de
la instancia RDS — separar ambos forzaria un acoplamiento cruzado mas
fragil que mantenerlos juntos. `secrets-bootstrap` queda **solo** para el
secret JWT, que es independiente de RDS.

Esto coincide con el naming ya autorizado en
`modules/oidc-github/policies/dev/spark-match-lambda-runtime.json:51`
(`secret:spark-match-${environment}-*`).

### 3. Runtime: env vars en vez de relectura de SSM

El codigo actual de `03-backend` (`composition.ts`, `db-connection.ts`,
`jwt-secret-loader.ts`) llama a SSM **en runtime** para resolver ARNs que
SAM **ya inyecto como env vars** en deploy-time via `{{resolve:ssm:}}`.
Es una relectura redundante del mismo valor inmutable.

Decision: el backend debe leer estos ARNs de `process.env` directamente
(cambio en `03-backend`, coordinado por chat, no trackeado como task file
aqui — ver seccion "Naming de branches y coordinacion cross-repo" en
AGENTS.md). Efecto en este repo: el catalogo de VPC endpoints **no
necesita** el endpoint `ssm` para el flujo de runtime (solo
`secretsmanager` para leer las credenciales frescas, y `events` para
`PutEvents`).

### 4. Topologia de red: VPC + 2 interface endpoints en 1 AZ, sin NAT

Las Lambdas del backend corren dentro de la VPC (subnet privada) para
llegar a RDS. Sin NAT (`enable_nat_gateway=false` en dev), las unicas
llamadas SDK salientes que necesitan salida son Secrets Manager (leer
credenciales) y EventBridge (`PutEvents`). Ambos se resuelven con
**interface endpoints** desplegados en **1 sola AZ** (no las 2) para
reducir costo: cada ENI adicional por AZ cuesta ~$7.20/mes por endpoint.

CloudWatch Logs y X-Ray **no requieren** NAT ni VPC endpoint: viajan por
el plano de control de Lambda, no por la ENI de la funcion.

### 5. VPC config para Lambda: subnet IDs + security group via SSM

Como las Lambdas corren dentro de la VPC (seccion 4), `03-backend` necesita
2 valores adicionales para configurar `AWS::Lambda::Function.VpcConfig` en
su template SAM: los IDs de las subnets privadas y el ID del security group
`sg-lambda` (creado en `modules/security-groups`, con `egress = []` inline
y reglas explicitas de salida hacia `sg-rds`/`sg-endpoints`).

Se exponen como parametros String adicionales bajo el mismo prefijo
`/spark-match/{env}/config/` (ver tabla en seccion 1) en vez de requerir un
paso manual de copiar IDs a variables de GitHub Actions, por 2 razones:

- Consistencia con el patron `{{resolve:ssm:}}` ya usado para los otros 6
  valores deploy-time — un solo mecanismo de resolucion, no dos.
- Evita drift: si la VPC se recrea (ej: cambio de CIDR), el proximo
  `terraform apply` actualiza el parametro SSM automaticamente y el
  siguiente `sam deploy` lo recoge sin intervencion humana. Una variable de
  GitHub Actions copiada a mano no se actualiza sola.

`private-subnet-ids` se almacena como CSV en un solo parametro String (no
como `StringList`, que tiene limitaciones de longitud y no es soportado por
`{{resolve:ssm:}}` en todos los contextos de CloudFormation); el template
SAM debe hacer `!Split [",", "{{resolve:ssm:...}}"]` para consumirlo.

## Consequences

### Positivas

- `dev` y `prod` quedan aislados aunque compartan cuenta AWS: un
  `sam deploy --config-env prod` nunca puede leer el secret de `dev`.
- El backend no necesita relectura de SSM en runtime → cold start mas
  rapido y menos superficie de IAM (se elimina `SSMParameterReadPolicy`
  de 8 de las 12 funciones que hoy no la tienen, y no hace falta agregarla
  a las 4 que si).
- Costo de red dev: ~$14.60/mes (2 endpoints × 1 AZ) en vez de ~$72/mes
  (10 endpoints × 2 AZ, si se hubiera activado el catalogo completo).

### Negativas

- Requiere un cambio coordinado en `03-backend` (mover de
  `{{resolve:ssm:/spark-match/db/secret-arn}}` a
  `{{resolve:ssm:/spark-match/${Environment}/config/db-secret-arn}}` en
  las plantillas SAM, y de lectura SSM runtime a `process.env` en el
  codigo). Sin este cambio, el backend seguiria apuntando a paths que
  Terraform ya no crea (los viejos, sin ambiente).
- Si en el futuro se agregan mas servicios AWS al runtime (ej: S3 para
  RAG documents), hay que evaluar caso por caso si necesitan su propio
  interface endpoint o si pueden esperar via NAT/gateway endpoint.

## Verification

```bash
# Confirmar que los 8 parametros existen post-apply:
aws ssm get-parameters-by-path --path "/spark-match/dev/config" --recursive \
  --profile spark-match-admin --query 'Parameters[].Name' --output table

# Confirmar que el secret de DB tiene las 5 keys esperadas:
aws secretsmanager get-secret-value --secret-id spark-match-dev-db-credentials \
  --profile spark-match-admin --query 'SecretString' --output text | jq 'keys'
# esperado: ["database","host","password","port","username"]
```

## References

- `docs/DECISIONS.md` (este repo) — principio de ARNs como identificadores.
- `modules/oidc-github/policies/dev/spark-match-lambda-runtime.json` — naming
  de secrets ya autorizado.
- `03-backend/template.yaml`, `03-backend/contexts/identity/template.yaml` —
  consumidores de estos parametros.
- `03-backend/contexts/identity/src/composition.ts`,
  `db-connection.ts`, `shared/src/auth/jwt-secret-loader.ts` — puntos de
  lectura runtime a migrar a env vars.
