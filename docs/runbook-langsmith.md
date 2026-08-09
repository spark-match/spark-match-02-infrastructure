# Runbook: API key de LangSmith para el agente

El deep-agent manda trazas a [LangSmith](https://smith.langchain.com): cada
llamada al modelo, cada tool y cada delegacion en un subagente, con su latencia
y sus tokens. Sin API key el agente **funciona igual**, solo que a ciegas: no se
manda nada y `configure_langsmith()` lo dice por WARNING en el arranque.

El cableado en el codigo ya existe (`src/observability/langsmith.py`, llamado
desde el lifespan de `src/api/app.py`). Este runbook cubre solo la parte de
infraestructura: de donde sale la key en dev.

## Un proyecto por ambiente

Las trazas caen en `spark-match-agent-{environment}`:

| Donde corre | Proyecto en LangSmith |
| --- | --- |
| Portatil (`.env`) | `spark-match-agent-local` |
| ECS dev | `spark-match-agent-dev` |
| ECS prod | `spark-match-agent-prod` |

El modulo lo calcula solo a partir de `project_name` + `environment`, asi que
`live/dev` no pasa ningun nombre. La variable `langsmith_project` existe por si
alguna vez hace falta apuntar a otro, pero lo normal es no tocarla.

Mezclarlos es justo lo que estorba cuando algo falla en dev y no en local:
media hora buscando por que una traza "no aparece" hasta caer en que estaba
mirando las del portatil de otro.

## Por que la key no esta en Terraform

Lo mismo que con Tavily (`runbook-tavily.md`): Terraform lee el ARN del secret,
nunca su valor. Un `aws_secretsmanager_secret_version` dejaria la key **en claro
dentro del tfstate**, que vive en S3 con versionado — borrarla despues no
serviria, quedan las versiones anteriores del objeto.

El valor lo pone una persona, una vez, fuera del pipeline.

## Crear el secret

Una sola vez por ambiente. La key se saca de <https://smith.langchain.com> →
Settings → API Keys; empieza por `lsv2_`.

```bash
aws secretsmanager create-secret \
  --name spark-match-dev-langsmith-api-key \
  --description "API key de LangSmith para el tracing del deep-agent (dev)" \
  --secret-string "lsv2_REEMPLAZAR" \
  --profile spark-match-admin --region us-east-1
```

`--secret-string` es la key tal cual, **string plano, no JSON**: asi lo espera
el `valueFrom` de la task definition, que apunta al secret entero sin sufijo de
clave.

Nota sobre el historial del shell: `create-secret` deja la key en el historial
de bash/PowerShell. Para evitarlo, `--secret-string file://ruta` y borrar el
fichero despues, o crearlo desde la consola de AWS.

Encriptacion: la key por defecto (`aws/secretsmanager`) esta bien — al
execution role le basta con `GetSecretValue`. Con la CMK del proyecto tambien
funciona: el role ya tiene `kms:Decrypt` sobre ella.

## Cablearlo

En `live/dev/terraform.tfvars`:

```hcl
agent_langsmith_secret_name = "spark-match-dev-langsmith-api-key"
```

Y aplicar. Terraform resuelve el ARN, lo mete en el bloque `secrets` de la task
definition como `SPARK_LANGSMITH_API_KEY`, le da `secretsmanager:GetSecretValue`
al execution role sobre ese ARN concreto, y pone `SPARK_LANGSMITH_TRACING=true`
y `SPARK_LANGSMITH_PROJECT=spark-match-agent-dev` como env vars normales.

El flag va atado al secret: con `agent_langsmith_secret_name = null`,
`SPARK_LANGSMITH_TRACING` queda en `false` y no hay WARNING de arranque
prometiendo trazas que nadie va a mandar.

El valor de la key **no** aparece en `aws ecs describe-task-definition` — ahi
solo se ve el ARN. Por eso va en `secrets` y no en `environment`.

### Aplicar NO alcanza: hay que mover el servicio a mano una vez

Identico al caso de Tavily, y por la misma razon: `aws_ecs_service` tiene
`ignore_changes = [task_definition]` y el CD (`reusable-ecs-deploy.yml`) parte
de **la revision que el servicio corre ahora mismo**, no de la ultima de la
familia. Una revision registrada por Terraform queda huerfana y el bloque
`secrets` nunca llega al contenedor, sin ningun error visible.

Despues de `terraform apply`:

```bash
aws ecs describe-task-definition --task-definition spark-match-agent-dev \
  --query 'taskDefinition.revision' --output text \
  --profile spark-match-admin --region us-east-1
# -> N

aws ecs update-service --cluster spark-match-dev --service spark-match-agent-dev \
  --task-definition spark-match-agent-dev:N --force-new-deployment \
  --profile spark-match-admin --region us-east-1
```

### "La revision mas nueva" puede no ser la de Terraform

El `N` de arriba viene de pedir la revision mas alta de la familia. Eso alcanza
solo si nadie mas registro una revision despues del `apply`. No es el caso si
un push a `dev` de **spark-match-08-deep-agent** cae cerca en el tiempo:
`deploy.yml` de ese repo corre en CUALQUIER push a `dev`, sin filtrar por que
cambio, y su `roll ecs` lee "la task definition actual" como base para
patchear solo la imagen.

Medido el 2026-08-09: un PR de infra (esta feature, revision 18 con el
secreto) y un PR de agente sin cambio de imagen (solo docs y un test) se
mergearon con 23 segundos de diferencia. `deploy.yml` leyo la base UN SEGUNDO
antes de que este `apply` terminara, registro su propia revision 19 a partir
de esa base vieja -- sin el secreto de LangSmith -- y movio el servicio ahi.
Encima de la revision buena, no en su lugar: la 18 con el secreto sigue
existiendo intacta, solo que el servicio ya no apunta a ella.

Nada de lo obvio lo delata. `rolloutState: COMPLETED` y el contenedor
`HEALTHY` son ciertos en la revision 19 tambien -- el contenedor arranca bien
sin LangSmith, solo que sin mandar trazas. Y re-correr `terraform apply` NO
arregla nada: Terraform no ve drift (su recurso, la revision 18, sigue
existiendo tal cual la creo) y `aws_ecs_service` tiene
`ignore_changes = [task_definition]` a proposito, asi que el plan sale limpio
y el `apply` se salta por no haber cambios.

Como detectarlo, en vez de confiar en el numero mas alto:

```bash
# La task definition que el servicio corre AHORA MISMO, no la ultima de la
# familia -- pueden ser distintas.
aws ecs describe-services --cluster spark-match-dev --services spark-match-agent-dev \
  --query 'services[0].deployments[?status==`PRIMARY`].taskDefinition' --output text \
  --profile spark-match-admin --region us-east-1

# Trae el secreto de LangSmith esa revision?
aws ecs describe-task-definition --task-definition spark-match-agent-dev:N \
  --query 'taskDefinition.containerDefinitions[0].secrets[?name==`SPARK_LANGSMITH_API_KEY`]' \
  --profile spark-match-admin --region us-east-1
```

Si sale vacio, buscar hacia atras (`:N-1`, `:N-2`, ...) la revision que si lo
tenga -- normalmente la que el propio `apply` acaba de crear -- y apuntar el
servicio ahi a mano, igual que en la seccion anterior pero con el numero
verificado, no el mas alto.

La prueba de fuego no es el estado del servicio, es el log de arranque (ver
"Verificar" mas abajo): `ENABLED` contra `disabled` no deja lugar a dudas.

## Verificar

Que la task definition trae las dos piezas:

```bash
aws ecs describe-task-definition --task-definition spark-match-agent-dev \
  --query 'taskDefinition.containerDefinitions[0].[secrets,environment[?starts_with(name,`SPARK_LANGSMITH`)]]' \
  --profile spark-match-admin --region us-east-1
```

Que el proceso lo cogio, en los logs de arranque:

```bash
aws logs tail /aws/spark-match/agent/dev/service --since 10m \
  --filter-pattern "LangSmith" \
  --profile spark-match-admin --region us-east-1
```

Tiene que decir `LangSmith tracing ENABLED (project=spark-match-agent-dev)`. Si
dice `disabled`, el `secrets` no llego al contenedor — casi siempre es el paso
de mover el servicio a mano que quedo pendiente.

Y por ultimo, un turno de chat real: la traza aparece en
<https://smith.langchain.com> bajo `spark-match-agent-dev` en unos segundos.

## Rotar

```bash
aws secretsmanager put-secret-value \
  --secret-id spark-match-dev-langsmith-api-key \
  --secret-string "lsv2_LA-NUEVA" \
  --profile spark-match-admin --region us-east-1
```

Terraform no se entera ni le hace falta: el ARN no cambia. Lo que si hace falta
es **reciclar el servicio**, porque ECS resuelve los `secrets` una sola vez, al
arrancar la task:

```bash
aws ecs update-service --cluster spark-match-dev \
  --service spark-match-agent-dev --force-new-deployment \
  --profile spark-match-admin --region us-east-1
```

## Que se manda, y como apagarlo

Una traza lleva **la conversacion entera**: lo que escribe el estudiante, lo que
responde el modelo, los argumentos de cada tool y el contenido que devuelven. Es
lo que hace util el tracing y tambien lo que hay que tener presente — son datos
de personas reales saliendo de la cuenta de AWS hacia un SaaS de terceros en
EEUU.

Para apagarlo: `agent_langsmith_secret_name = null` en `terraform.tfvars`,
aplicar y reciclar el servicio. El agente levanta igual, sin tracing. No hace
falta borrar el secret.

Si en algun momento hay que retener menos, LangSmith admite `LANGSMITH_ENDPOINT`
(region EU) y reglas de retencion por proyecto; el modulo no las expone todavia
porque hoy no hacen falta.

## Ojo con el nombre de la variable en local

El `.env` local usa `SPARK_LANGSMITH_API_KEY`, con prefijo `SPARK_` como el
resto de settings. Un `.env` con `LANGSMITH_API_KEY` a secas **no lo lee
`Settings`** — aunque, a diferencia de Tavily, LangChain si leeria esa variable
por su cuenta y el tracing acabaria funcionando "por accidente", saltandose
`configure_langsmith()` y su eleccion de proyecto. Las trazas caerian en
`default`. Ver `.env.example` en spark-match-08-deep-agent.
