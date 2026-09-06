# Runbook: API key de Tavily para el agente

`web_search` del deep-agent usa Tavily como proveedor principal y DuckDuckGo
como fallback. Sin API key la herramienta no revienta, pero **el fallback no es
una degradacion suave**. Medido en los logs de dev el 2026-08-08:

```
Tavily search failed (ValueError), falling back to DuckDuckGo:
  TAVILY_API_KEY not configured
Web search completed via DuckDuckGo (fallback): 0 results
```

Cero resultados, no peores resultados. Cualquier pregunta que dependa de
informacion actual (fechas de Beca 18, admisiones) se queda sin responder.

## Como se reparte esto — ver [ADR-0003](adr/0003-api-keys-terceros-contenedor-terraform-valor-ci.md)

| Quien | Que |
|---|---|
| Terraform | Crea el **contenedor** del secret: nombre, KMS, ventana de recuperacion, tags, y el permiso del execution role |
| Job `push-agent-api-keys` del workflow de apply | Escribe el **valor**, leyendolo del GitHub Environment secret `TAVILY_API_KEY` |

Terraform nunca ve la key. Si la escribiera con un
`aws_secretsmanager_secret_version`, quedaria **en claro dentro del tfstate**,
que vive en S3 con versionado: cualquiera con acceso al bucket podria leerla, y
borrarla despues no serviria porque quedan las versiones anteriores del objeto.

Antes de este reparto el secret se creaba a mano y Terraform lo leia con un
`data` source. Se cambio porque un data source ausente **falla el plan entero**:
cuando el reset de la cuenta AWS Academy borro el secret, `plan-dev` quedo en
rojo en todos los PR del repositorio.

## Alta: cargar la key una vez por ambiente

La key se saca de <https://tavily.com> (el plan gratuito da 1.000
busquedas/mes).

**1. Cargarla en el GitHub Environment.** En
`spark-match/spark-match-02-infrastructure` → *Settings* → *Environments* →
`dev` (o `production`) → *Environment secrets* → *Add secret*:

```
Name:   TAVILY_API_KEY
Value:  tvly-...
```

Va como **string plano, no JSON**: asi lo espera el `valueFrom` de la task
definition, que apunta al secret entero sin sufijo de clave.

A diferencia de `aws secretsmanager create-secret`, esto no deja la key en el
historial del shell.

**2. Activar el flag.** En `live/dev/terraform.tfvars`:

```hcl
agent_tavily_enabled = true
```

**3. Aplicar.** Al mergear a `dev`, el workflow de apply crea el secret y el job
`push-agent-api-keys` le inyecta el valor.

> Si se activa el flag **sin** haber cargado el secret en el Environment, el job
> falla a proposito con un error que lo dice. Es preferible a que el agente
> arranque con el centinela que pone Terraform y descubrirlo despues como un 401
> de Tavily que nadie relaciona con un apply.

Terraform le da al execution role `secretsmanager:GetSecretValue` sobre ese ARN
concreto, y ECS resuelve el valor al arrancar la task y lo inyecta como
`SPARK_TAVILY_API_KEY`. El valor **no** aparece en
`aws ecs describe-task-definition` — ahi solo se ve el ARN. Por eso va en
`secrets` y no en `environment`.

## Aplicar NO alcanza: hay que mover el servicio a mano una vez

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

Ya no se toca AWS a mano. Se actualiza el Environment secret y se relanza el
apply:

1. *Settings* -> *Environments* -> `dev` -> `TAVILY_API_KEY` -> *Update*.
2. Lanzar `continuous-deployment-terraform-apply-dev` (workflow_dispatch, o
   cualquier merge a `dev`). El job `push-agent-api-keys` detecta que el valor
   cambio y escribe una version nueva del secret.

El job compara antes de escribir, asi que relanzar el apply sin cambiar la key
no crea versiones nuevas: AWS solo conserva las 100 ultimas.

Terraform no se entera ni le hace falta, el ARN no cambia. Lo que si hace falta
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
spark-match-07-deep-agent.

## Presupuesto de busquedas

`SPARK_MAX_WEB_SEARCHES_PER_SESSION` limita cuantas busquedas puede hacer el
agente. **`0` no desactiva la herramienta, desactiva el limite**
(`handler.py` trata `cap <= 0` como ilimitado). El modulo lo deja en 6.

Ese contador ademas se reinicia en cada request HTTP, no por conversacion, asi
que el tope real es 6 por mensaje. Con 1.000 busquedas/mes del plan gratuito
conviene tenerlo presente antes de abrir el chat a usuarios reales.
