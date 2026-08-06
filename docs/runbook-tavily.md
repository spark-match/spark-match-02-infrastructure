# Runbook: API key de Tavily para el agente

`web_search` del deep-agent usa Tavily como proveedor principal y DuckDuckGo
como fallback. Sin API key la herramienta **sigue funcionando**, solo que
siempre por DuckDuckGo (resultados peores para consumo de un LLM).

## Por que la key no esta en Terraform

Terraform lee el ARN del secret, nunca su valor. Si el valor se creara con un
`aws_secretsmanager_secret_version`, quedaria **en claro dentro del tfstate**,
que vive en S3 con versionado: cualquiera con acceso al bucket podria leerlo, y
borrarlo despues no serviria de nada porque quedan las versiones anteriores del
objeto.

Por eso el valor lo pone una persona, una vez, fuera del pipeline.

## Crear el secret

Una sola vez por ambiente. La key se saca de <https://tavily.com> (el plan
gratuito da 1.000 busquedas/mes).

```bash
aws secretsmanager create-secret \
  --name spark-match-dev-tavily-api-key \
  --description "API key de Tavily para web_search del deep-agent (dev)" \
  --secret-string "tvly-REEMPLAZAR" \
  --profile spark-match-admin --region us-east-1
```

El `--secret-string` es la key tal cual, **string plano, no JSON**: asi lo
espera el `valueFrom` de la task definition, que apunta al secret entero sin
sufijo de clave.

Nota sobre el historial del shell: `create-secret` deja la key en el historial
de bash/PowerShell. Para evitarlo, `--secret-string file://ruta` y borrar el
fichero despues, o crearlo desde la consola de AWS.

Encriptacion: dejar la key por defecto (`aws/secretsmanager`) esta bien — el
execution role del agente ya puede descifrarla con solo tener
`GetSecretValue`. Si se usa la CMK del proyecto tambien funciona: el role ya
tiene `kms:Decrypt` sobre ella.

## Cablearlo

En `live/dev/terraform.tfvars`:

```hcl
agent_tavily_secret_name = "spark-match-dev-tavily-api-key"
```

Y aplicar. Terraform resuelve el ARN, lo mete en el bloque `secrets` de la task
definition y le da `secretsmanager:GetSecretValue` al execution role sobre ese
ARN concreto. ECS resuelve el valor al arrancar la task y lo inyecta como
`SPARK_TAVILY_API_KEY`.

El valor **no** aparece en `aws ecs describe-task-definition` — ahi solo se ve
el ARN. Por eso va en `secrets` y no en `environment`.

### Aplicar NO alcanza: hay que mover el servicio a mano una vez

`aws_ecs_service` tiene `ignore_changes = [task_definition]` (el CD es el dueño
de que imagen corre). Y el CD, en `reusable-ecs-deploy.yml`, parte de **la
revision que el servicio corre ahora mismo**, no de la ultima de la familia.

Las dos cosas juntas significan que una revision registrada por Terraform queda
**huerfana**: el servicio sigue en la vieja, y el siguiente deploy del agente
tambien parte de la vieja. El bloque `secrets` nunca llegaria al contenedor y no
habria ningun error — el agente seguiria buscando por DuckDuckGo.

Despues de `terraform apply`, apuntar el servicio a la revision nueva una sola
vez:

```bash
aws ecs describe-task-definition --task-definition spark-match-agent-dev \
  --query 'taskDefinition.revision' --output text \
  --profile spark-match-admin --region us-east-1
# -> N

aws ecs update-service --cluster spark-match-dev --service spark-match-agent-dev \
  --task-definition spark-match-agent-dev:N --force-new-deployment \
  --profile spark-match-admin --region us-east-1
```

A partir de ahi el CD arranca desde la revision buena y conserva el `secrets`
en cada deploy.

Detalle menor: la revision que registra Terraform apunta a la imagen por **tag**
(`:latest`), mientras que las del CD la fijan por digest. Al mover el servicio a
mano se pierde ese pin hasta el siguiente deploy del agente, que vuelve a
fijarlo. Mismo contenido de imagen, distinta forma de referenciarla.

## Verificar

```bash
aws ecs describe-task-definition --task-definition spark-match-agent-dev \
  --query 'taskDefinition.containerDefinitions[0].secrets' \
  --profile spark-match-admin --region us-east-1
```

Y despues, en el chat, una pregunta que obligue a buscar. En los logs del
agente el resultado de `web_search` trae `"provider": "tavily"` en vez de
`"duckduckgo"`.

## Rotar

```bash
aws secretsmanager put-secret-value \
  --secret-id spark-match-dev-tavily-api-key \
  --secret-string "tvly-LA-NUEVA" \
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

## Ojo con el nombre de la variable en local

El `.env` local usa `SPARK_TAVILY_API_KEY` (prefijo `SPARK_`, igual que el
resto de settings). Un `.env` con `TAVILY_API_KEY` a secas **no lo lee nadie** y
el agente cae a DuckDuckGo sin avisar. Ver `.env.example` en
spark-match-08-deep-agent.

## Presupuesto de busquedas

`SPARK_MAX_WEB_SEARCHES_PER_SESSION` limita cuantas busquedas puede hacer el
agente. **`0` no desactiva la herramienta, desactiva el limite**
(`handler.py` trata `cap <= 0` como ilimitado). El modulo lo deja en 6.

Ese contador ademas se reinicia en cada request HTTP, no por conversacion, asi
que el tope real es 6 por mensaje. Con 1.000 busquedas/mes del plan gratuito
conviene tenerlo presente antes de abrir el chat a usuarios reales.
