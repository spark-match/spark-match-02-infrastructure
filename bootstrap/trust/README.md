# Trust policies de los cuatro roles de Terraform

Quien puede asumir cada rol. El directorio hermano `../policies/` declara lo
contrario: que puede hacer cada rol una vez asumido.

Estos cuatro documentos no los gestiona Terraform, por el mismo motivo que las
policies de al lado: son los roles que Terraform usa para correr, asi que no
puede crearlos.

## Por que existe este directorio (2026-08-07)

Hasta hoy las trust policies **no estaban en ningun sitio versionado**. Vivian
solo en AWS, editadas a mano, y lo que habia en los cuatro roles era esto:

    repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/dev
    repo:spark-match/spark-match-02-infrastructure:ref:refs/heads/main
    repo:spark-match/spark-match-02-infrastructure:pull_request
    repo:spark-match/spark-match-02-infrastructure:environment:dev
    repo:spark-match/spark-match-02-infrastructure:environment:production
    repo:spark-match/spark-match-02-infrastructure:workflow_dispatch
    repo:spark-match@*/spark-match-02-infrastructure@*:ref:refs/heads/dev
    repo:spark-match@*/spark-match-02-infrastructure@*:ref:refs/heads/main
    repo:spark-match@*/spark-match-02-infrastructure@*:pull_request
    repo:spark-match@*/spark-match-02-infrastructure@*:environment:dev
    repo:spark-match@*/spark-match-02-infrastructure@*:environment:production
    repo:spark-match@*/spark-match-02-infrastructure@*:workflow_dispatch

Los doce, **identicos en los cuatro roles**. Tres problemas:

1. El rol que escribe en produccion aceptaba `refs/heads/dev`. Un workflow
   corriendo en la rama de desarrollo podia asumirlo.
2. Aceptaba `pull_request`. Cualquier pull request que pidiera ese rol lo
   obtenia.
3. Los seis `spark-match@*/...@*` son comodines que vienen del commit
   `f26573d chore: trigger apply-prod with permissive OIDC trust policy for
   debug (#33)`, del 13 de julio. Se abrieron para depurar y nadie los cerro.

O sea que la separacion entre dev y produccion existia en GitHub pero **no en
AWS**. Lo que impedia un accidente era que los workflows estan bien escritos y
que `apply-prod` tiene puerta de aprobacion; la frontera de IAM, que deberia ser
la ultima defensa, no separaba nada.

## De donde sale cada valor

No de criterio: de leer que `sub` emite cada workflow.

| Rol | `sub` que necesita | Por que |
|---|---|---|
| `plan-dev` | `pull_request` y `environment:dev` | `terraform-plan-dev.yml` pasa `environment: ${{ github.event_name != 'pull_request' && 'dev' \|\| '' }}`. En un pull request el environment queda VACIO, asi que el token sale como `:pull_request`. En `workflow_dispatch` bindea `dev`. |
| `apply-dev` | `environment:dev` | `terraform-apply-dev.yml` pasa `gh-environment: dev` siempre, tanto en el push a `dev` como en el dispatch. |
| `plan-prod` | `environment:production` | Solo `workflow_dispatch`, y bindea `production`. Nunca corre en un pull request. |
| `apply-prod` | `environment:production` | `gh-environment: production` siempre, en el push a `main` y en el dispatch. |

Cuando el job bindea un GitHub Environment, el `sub` del token es
`repo:<owner>/<repo>:environment:<nombre>` y no incluye la rama. Por eso el
claim de environment es a la vez el mas estrecho y el suficiente: la rama ya la
controla la branch policy del propio environment en GitHub.

## Aplicarlas

    python bootstrap/apply-bootstrap-policies.py dev            # dry-run
    python bootstrap/apply-bootstrap-policies.py dev --apply
    python bootstrap/apply-bootstrap-policies.py prod --apply

El script hace `update-assume-role-policy`, que **reemplaza** el documento
entero: no fusiona nada con lo que hubiera antes.

Correrlo dos veces seguidas no escribe la segunda vez. Compara lo vigente con
lo versionado y, si coinciden, imprime `sin cambios` y no llama a IAM.

## Volver atras

La marcha atras es **re-aplicar lo que hay en este directorio**, no un fichero
suelto de un respaldo. Estos cuatro JSON son la fuente de verdad; el respaldo
es una copia local y de conveniencia.

Antes de sobreescribir, el script guarda la policy vigente en `backups/trust/`,
que esta en `.gitignore`. El nombre sin sufijo es el estado anterior a la
**primera** ejecucion; las veces siguientes van a `<rol>.1.json`, `<rol>.2.json`
y asi. Nunca pisa un respaldo anterior, y esa parte importa: el 2026-08-07 si
lo pisaba, el script corrio dos veces sobre los mismos roles y el respaldo
acabo conteniendo la policy nueva. Seguia imprimiendo `respaldo en ...` y el
fichero seguia ahi, asi que la marcha atras parecia cubierta cuando ya no lo
estaba.

Si hace falta restaurar un respaldo concreto:

    aws iam update-assume-role-policy --role-name <rol> \
      --policy-document file://backups/trust/<rol>.json \
      --profile spark-match-admin

Los doce patrones que habia antes de versionar esto estan transcritos mas
arriba, asi que el estado previo se puede reconstruir a mano aunque no quede
ningun respaldo.

## Si un despliegue deja de poder asumir el rol

El sintoma es `Not authorized to perform sts:AssumeRoleWithWebIdentity` en el
step de credenciales. Significa que el `sub` real no esta en la lista. Para ver
el real, sin adivinar:

    gh run view <run-id> --log | grep -i "sub\|assume"

Y si hace falta desbloquear ya, corrige el JSON de este directorio y vuelve a
aplicarlo. No editar a mano en la consola de IAM: eso es exactamente como
llegamos a los doce patrones, y un arreglo que no pasa por aqui se pierde en
cuanto alguien vuelva a correr el script.
