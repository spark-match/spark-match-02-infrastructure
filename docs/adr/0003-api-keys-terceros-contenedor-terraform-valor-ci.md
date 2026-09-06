# ADR 0003 — API keys de terceros: Terraform crea el contenedor, CI inyecta el valor

> **Status**: accepted
> **Date**: 2026-09-06
> **Deciders**: @ahincho
> **Extiende**: [ADR 0002](0002-cross-repo-config-contract-ssm-secrets.md) (seccion 2, ownership de secrets)

## Context

El agente (`spark-match-07-deep-agent`) necesita dos API keys emitidas por
terceros: Tavily, para `web_search`, y LangSmith, para el tracing. A diferencia
del secret JWT y de las credenciales de RDS, **estos valores no los puede
generar Terraform**: los emite un proveedor externo y hay que ir a su consola a
pedirlos.

Hasta este ADR el reparto era:

- Un humano creaba el secret a mano siguiendo `docs/runbook-tavily.md` /
  `docs/runbook-langsmith.md`.
- Terraform lo leia con un `data "aws_secretsmanager_secret"` y solo usaba el
  ARN para inyectarlo en la task de ECS.

Ese reparto fallo de tres maneras distintas, todas medidas:

**1. Un data source ausente rompe el plan entero.** El reset de la cuenta AWS
Academy (ADR-003 del knowledge-base) borro los dos secrets. Desde ese momento
`terraform plan` abortaba con:

```
Error: reading Secrets Manager Secret (spark-match-dev-tavily-api-key):
  couldn't find resource
```

No es que fallara el modulo del agente: falla el plan completo, asi que el check
`plan-dev` salio rojo **en todos los PR del repositorio**, incluidos los que no
tocaban infraestructura.

**2. El parche para esquivarlo era fragil.** Se anadio
`agent_tavily_secret_name = null` para sacar el data source del grafo (PR #224).
El PR #226, el del renumerado de repositorios, lo revirtio sin querer al
resolver un conflicto sobre el mismo fichero, y `plan-dev` volvio a rojo durante
cinco dias sin que nadie lo relacionara con aquello. Un flag que hay que
acordarse de mantener es un flag que se pierde.

**3. El valor solo existia en la cabeza de quien lo creo.** Cuando la cuenta se
vacio, no habia de donde recuperarlo salvo volviendo a la consola de Tavily.
Nada en el repositorio ni en la organizacion guardaba ese estado.

La alternativa obvia —que Terraform escriba tambien el valor con un
`aws_secretsmanager_secret_version`— resuelve 1, 2 y 3 pero introduce un
problema peor: **el valor quedaria en claro en el tfstate**, que vive en S3 y es
legible por cualquiera con acceso al bucket, en cada version del objeto. Para el
JWT eso es tolerable porque el tfstate es su unica casa y el valor lo genero
Terraform; para una credencial de un servicio externo de pago no lo es.

## Decision

Se separan **contenedor** y **valor**:

| Responsable | Que hace |
|---|---|
| Terraform (`modules/agent-service`) | Crea `aws_secretsmanager_secret` (nombre, KMS, ventana de recuperacion, tags) y una version centinela |
| Job `push-agent-api-keys` del workflow de apply | Escribe el VALOR con `aws secretsmanager put-secret-value`, leyendolo de un GitHub Environment secret |

Terraform **nunca ve la key**. El valor viaja del GitHub Environment al runner y
del runner a la API de Secrets Manager; no pasa por el tfstate ni por la salida
del plan.

### 1. Interfaz: booleanos, no nombres

`tavily_secret_name` / `langsmith_secret_name` (string nullable, el nombre de un
secret preexistente) pasan a ser `tavily_enabled` / `langsmith_enabled` (bool).

El nombre lo deriva el modulo:

```
{project_name}-{environment}-tavily-api-key
{project_name}-{environment}-langsmith-api-key
```

Ese prefijo no es cosmetico: es el que autorizan las policies de bootstrap
(`secret:spark-match-${environment}-*`, ver
`bootstrap/policies/spark-match-tf-apply-*.json`) y el mismo criterio de naming
que fija el ADR-0002 seccion 2. La formula se repite en tres sitios —el modulo,
el workflow y las policies— y los tres llevan un comentario que lo advierte.

### 2. Version centinela con `ignore_changes`

Terraform crea una primera version con el literal
`PENDIENTE-DE-INYECTAR-POR-EL-WORKFLOW-DE-APPLY` y marca
`lifecycle { ignore_changes = [secret_string] }`.

El centinela hace falta porque un secret sin ninguna version hace fallar
`GetSecretValue`, y la task de ECS no arranca con un error que no explica por
que. Con el centinela el contenedor levanta y, si nadie inyecto la key, el fallo
aparece donde se entiende: en la llamada al proveedor.

`ignore_changes` evita que el apply siguiente pise el valor real. Es el mismo
mecanismo que `modules/secrets-bootstrap` ya usa con el JWT.

### 3. El job falla si el flag esta activo y la key no

`push-agent-api-keys` distingue dos situaciones:

- **El secret no existe en AWS** → el flag de Terraform esta en `false`. Notice
  informativo y salida 0.
- **El secret existe pero el GitHub Environment secret esta vacio** → error y
  salida 1.

Fallar aqui es deliberado. La alternativa —seguir adelante— deja el agente
corriendo con el centinela, y el sintoma llega mucho despues como un 401 del
proveedor que nadie relaciona con un apply de infraestructura.

El job compara el valor vigente antes de escribir, para no crear una version
nueva del secret en cada apply: AWS solo conserva las 100 ultimas.

### 4. El environment se bindea en el job

`environment: dev` / `environment: production` se declara **en el job**, no en el
caller de un reusable. Un secret con scope de environment es invisible en el
bloque `with:`/`secrets:` de quien llama a un workflow reutilizable —la trampa
que dejo 20 ejecuciones fallidas en `terraform-apply-prod.yml` y esta
documentada en su cabecera—. Al bindearlo en el job propio, tanto
`secrets.AWS_APPLY_ROLE_ARN` como las API keys se resuelven con normalidad.

Efecto lateral util en prod: el Environment `production` tiene required
reviewers, asi que la inyeccion del valor espera aprobacion humana.

### 5. Sin cambios de IAM

El rol de apply ya tiene lo necesario, con el alcance correcto:

| Policy | Acciones | Recurso |
|---|---|---|
| `spark-match-tf-apply-create` | `CreateSecret`, `DeleteSecret`, `UpdateSecretVersionStage` | `secret:spark-match-${environment}-*` |
| `spark-match-tf-apply-refresh` | `DescribeSecret`, `GetSecretValue`, `PutSecretValue`, `UpdateSecret`, `TagResource`, … | `secret:spark-match-${environment}-*` |

Por eso el naming derivado importa: mantenerlo dentro de
`spark-match-{env}-*` es lo que hace que este ADR no requiera tocar
`bootstrap/`, que es codigo que el propio rol no puede arreglarse a si mismo si
se rompe.

## Consequences

### Positivas

- **El plan deja de ser rehen del entorno.** Un recurso no puede faltar; si no
  esta, Terraform lo crea. Desaparece la clase de fallo que tuvo `plan-dev` en
  rojo cinco dias, y con ella el flag `= null` que habia que recordar mantener.
- **La cuenta se puede reconstruir sola.** Si AWS Academy vuelve a resetear la
  cuenta, un apply recrea los secrets y el job vuelve a inyectar los valores
  desde los Environments. Hoy eso dependia de que alguien tuviera las keys a mano.
- **El valor no entra en el tfstate**, que era la razon original de leerlos con
  un data source. Se conserva esa propiedad y se pierde la fragilidad.
- **Queda auditado quien cambia una key**, en el historial del Environment, en
  vez de en el shell de quien corrio `create-secret`.
- Los runbooks pasan de procedimiento manual a "carga esto en el Environment".

### Negativas

- **Los secrets de GitHub son de solo escritura.** Se ponen pero no se leen, asi
  que el Environment es un punto de inyeccion, no una copia consultable. La
  fuente legible sigue siendo Secrets Manager.
- **La formula del nombre vive en tres sitios** (modulo, workflow, policies de
  bootstrap). No hay forma de compartirla entre Terraform y un job de Actions sin
  acoplar mas cosas; se mitiga con comentarios cruzados en los tres.
- **Un apply puede fallar por un secret que falta**, no solo por infraestructura.
  Es deliberado (seccion 3), pero cambia lo que significa un apply rojo.
- **El primer apply con el flag activo crea el secret con el centinela y lo
  actualiza en el mismo run.** La task de ECS puede alcanzar a arrancar con el
  centinela si el despliegue del servicio va por delante; se corrige sola en el
  siguiente ciclo de la task.

## Verification

```bash
# 1. El secret existe y lo gestiona Terraform
aws secretsmanager describe-secret \
  --secret-id spark-match-dev-tavily-api-key \
  --query '{Nombre:Name,KMS:KmsKeyId,Tags:Tags[?Key==`ManagedBy`]}'

# 2. El valor NO es el centinela (o sea, el job lo inyecto)
test "$(aws secretsmanager get-secret-value \
  --secret-id spark-match-dev-tavily-api-key \
  --query SecretString --output text)" \
  != "PENDIENTE-DE-INYECTAR-POR-EL-WORKFLOW-DE-APPLY" \
  && echo "valor inyectado" || echo "AUN CON EL CENTINELA"

# 3. La key no aparece en el tfstate
terraform state pull | grep -c "tavily" # solo metadatos: nombre, ARN, tags

# 4. El plan no depende de que el secret exista: destruirlo y planificar
#    debe proponer recrearlo, no abortar.
```

## Notas de migracion

- No hace falta importar nada: los dos secrets **no existen** en la cuenta (los
  borro el reset), asi que Terraform los crea limpios.
- `secrets_recovery_window_in_days` es 0 en dev y 30 en prod. Con 30, borrar un
  secret lo deja en cuarentena ocupando el nombre: un `CreateSecret` posterior
  con el mismo nombre falla hasta que expire o se fuerce con
  `--force-delete-without-recovery`. Es el comportamiento que se quiere en prod.
- Los flags quedan en `false` en ambos ambientes hasta que se carguen las keys
  en los Environments. Activarlos antes hace fallar el job a proposito.
