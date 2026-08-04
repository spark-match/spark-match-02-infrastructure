# AGENTS.md

Convenciones operacionales para el repo `spark-match-02-infrastructure`.
Lectura obligatoria antes de cada PR. Fuente de verdad local (no duplicada en docs/).

---

## Proyecto

**Spark Match** — Plataforma de matching academico-industrial con componentes
multi-repo (spark-match-00-knowledge-base, 01-devops, 02-infrastructure, 03-backend,
04-frontend, 05-data-pipeline, 06-model-training, 07-article, 08-deep-agent).

Este repo define la **infraestructura AWS del proyecto** (VPC, IAM, KMS, SGs,
endpoints, observability base) usando Terraform modular y workflows reutilizables
desde `spark-match-01-devops`.

## Stack

- **Cloud**: AWS (us-east-1, cuenta `681526276858`).
- **IaC**: Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 6.0`.
- **AWS CLI local**: perfiles `spark-match-admin` (AdministratorAccess) o
  `orion-admin` (mismo nivel, uso compartido).
- **Backend**: S3 + native S3 lockfile (`use_lockfile = true`, sin DynamoDB).
- **CI/CD**: GitHub Actions, reusable workflows desde `spark-match-01-devops`
  pinneados `@main`.
- **Ambientes AWS**: 2 ambientes (`dev`, `prod`). El model de environments
  sigue la guia de `orion-infrastructure/AGENTS.md` (ramas multiples + GH
  Environment + OIDC role). Ver seccion "Multi-env".

## Convenciones Terraform / GH Actions vars

- **`TF_VERSION`** es la unica variable de GitHub Actions estrictamente
  necesaria a nivel repo. Se puede extender con `PLAN_ROLE_ARN`,
  `APPLY_ROLE_ARN`, `BACKEND_BUCKET`, etc. per env.
- **Resto de inputs** (environment, working-directory, aws-region, backend-bucket,
  backend-key, comment-on-pr, auto-approve) viven **hardcoded** en los
  workflows `terraform-plan-{env}.yml` y `terraform-apply-{env}.yml` por la
  limitacion de GitHub Actions: un job que invoca un reusable workflow via
  `uses:` no puede declarar `environment:` (regla de GH Actions, actionlint lo detecta),
  y por tanto no puede acceder a GH Environment variables desde ese contexto.
  La unica var accesible son las repo-scoped.

## Multi-env (dev + prod)

| Env     | Branch | GH Environment | AWS Account      | Region   | Backend bucket               |
| ------- | ------ | -------------- | ---------------- | -------- | ---------------------------- |
| dev     | dev    | dev            | 681526276858     | us-east-1 | `spark-match-tfstate-dev`  |
| prod    | main   | production     | 681526276858     | us-east-1 | `spark-match-tfstate-prod` |

- PR target: cada cambio se mergea a `dev` primero. La rama `main` se sincroniza
  via merge commits periodicos (sin fast-forward) o via workflow manual.
- Squash-only en el merge a dev (regla del repo).
- Branch deletion on merge (regla del repo).
- Ruleset activo: `spark-match-default-branch-protection` (1 approval + team
  review + status checks `Plan (dev)`, `Checkov`).

## Sync process (branch -> dev -> main) — regla operacional

> **Regla operacional**: el flujo canonico de un cambio cualquiera es
> `branch -> dev -> main`, en ese orden estricto. Nunca se commitea directo
> a `dev` o `main`. Nunca se mergea un feature branch directamente a `main`.

### 1. Branch feature (work local)

```bash
git checkout dev
git pull --ff-only
git checkout -b feat/sprint-N-{name}   # o fix/sprint-N-{name} / chore/sprint-N-{name}
git push -u origin feat/sprint-N-{name}
# crear PRs incrementales desde esta branch contra dev
```

### 2. PR a `dev` (work integration)

- PR target: `dev`.
- Squash merge (regla del repo).
- Branch deletion on merge (regla del repo).
- En este momento `dev` ya contiene el cambio, pero `main` no.

### 3. Sync a `main` (release a produccion)

- PR target: `main`.
- Squash merge con titulo `chore: sync dev into main (sprint N - <resumen>)`.
- Branch deletion on merge.

**Cuando promover dev -> main** (criterios, en orden de precedencia):

| Trigger | Categoria | Ejemplo |
|---|---|---|
| Sprint cerrado y QA aprobado | **Madurez** | Sprint 12 cerrado, tests OK |
| Code freeze planificado | **Madurez** | Fecha de release definida |
| Hotfix critico operacional | **Decision explicita** | Patch de seguridad urgente |
| Release planeado a produccion | **Decision explicita** | Deploy window agendado |

NO se sincroniza:
- Despues de cada PR a dev (overhead innecesario).
- Sin que el desarrollo lo indique explicitamente (en comentario del PR,
  en daily, o en task tracking).
- Cuando hay un check rojo o alerta CodeQL/Dependabot abierta (regla dura
  ya existente en seccion "Prioridad de alertas de seguridad").

> **Regla**: si dudas, NO sincronices. main queda libre de cambios hasta
> que el owner del sprint o el desarrollo indique lo contrario.

### 4. Verificacion post-sync (OBLIGATORIA)

Despues de CADA sync a `main`, verificar que el contenido es identico:

```bash
git fetch origin
git diff --stat origin/main origin/dev
# output esperado: (vacio, sin lineas)
```

Si el diff NO esta vacio, significa que main perdio cambios de dev. NO
avanzar hasta reconciliar (abrir PR de sync correctivo).

### 5. Por que `git log` muestra divergencia aunque el contenido sea igual

El sync a `main` usa `git merge --squash origin/dev`. Esto crea UN commit
en `main` que NO tiene como ancestros a los commits originales de `dev`.

Consecuencia:

```bash
git log origin/main..origin/dev   # 30+ commits (esperado, no es bug)
git log origin/dev..origin/main   # 0..1 commits (sync commit)
```

**Esto es esperado** y NO indica desactualizacion. La verificacion de
sincronizacion real es el paso 4: `git diff --stat origin/main origin/dev`
(espera vacio).

### Anti-patterns

- **Sincronizar main <- dev con `git merge --no-ff`**: deja un merge commit
  con dos parents, complica la lectura del historial. Use siempre
  `--squash` para sync PRs.
- **Sincronizar dev <- main (`git merge origin/main` en dev)**: rompe el
  flujo canonico. Solo valido en emergencias operativas documentadas.
- **Asumir que `git log` divergente = desactualizacion**: falso. Validar
  siempre con `git diff --stat`.

### Workflow automatizado (futuro Sprint 13)

Pendiente: crear workflow `.github/workflows/check-sync.yml` que corra en
cron semanal (`schedule: cron: '0 0 * * 0'`) y falle si el `git diff`
NO esta vacio. Notifica via Slack o abre issue automatica.

## Terminología unificada: solo "Sprint N" (regla dura)

> **Regla dura**: a partir del 2026-07-31, toda referencia a fases, tracks o
> implementation phases se hace **exclusivamente** como **"Sprint N"** (con N
> entero, sin prefijos ni sufijos). NO se usan los siguientes términos en
> código, docs, tasks, commits, branch names, labels, ni PR descriptions:
>
> - ❌ `Track A`, `Track B`, `track-A`, `track-B`
> - ❌ `Impl-2`, `Impl-3`, `Impl-4`, `Impl-5`, `impl-2`, `impl-3`, `impl-4`, `impl-5`
> - ❌ `Prod-1` a `Prod-6`, `prod-1` a `prod-6`
> - ❌ `preflight`, `Preflight` (como categoría independiente)
> - ❌ `A1`-`A30`, `B1`-`B6` (sin contexto de sprint)
>
> **Equivalencias canónicas** (usar siempre estas):
>
> | Concepto antiguo | Término unificado |
> | ---------------- | ----------------- |
> | Sprint 1 RECREATE | **Sprint 1** |
> | preflight 01-08 (8 quality gates) | **Sprint 2** (sub-items: `Sprint 2-NN`) |
> | Track A, Impl-2, foundation | **Sprint 3** |
> | Track A, Impl-3, database/observability | **Sprint 4** |
> | Track A, Impl-4, deploy automation | **Sprint 5** |
> | Track A, Impl-5, hardening | **Sprint 6** |
> | Track B, Prod-1 a Prod-6, production | **Sprint 7 a Sprint 12** |
> | Sprint 7 (Prod-1) | **Sprint 7** |
> | Sprint 8 (Prod-2) | **Sprint 8** |
> | Sprint 9 (Prod-3) | **Sprint 9** |
> | Sprint 10 (Prod-4) | **Sprint 10** |
> | Sprint 11 (Prod-5) | **Sprint 11** |
> | Sprint 12 (Prod-6) | **Sprint 12** |
>
> **Convenciones de naming derivadas**:
>
> - **Branch names**: `feat/sprint-N-*`, `fix/sprint-N-*`, `chore/sprint-N-*`
>   (NO usar `feat/impl-N-*` ni `feat/prod-N-*`).
> - **Task files** (estructura de sprints con carpetas):
>   - **Carpetas**: `tasks/infra/pending/sprint-N/` (activas) o
>     `tasks/infra/archive/sprint-N/` (cerradas). La carpeta provee el
>     contexto del sprint.
>   - **Filenames**: SIN fecha, SIN prefijo `sprint-N`. Solo `overview.md`,
>     `NN-{name}.md`, o `99-{name}-tracking.md`.
>   - **Overview**: `tasks/infra/pending/sprint-N/overview.md` — 1 archivo
>     por Sprint (contexto, scope, acceptance criteria sprint-level, lista
>     de subtasks).
>   - **Subtask**: `tasks/infra/pending/sprint-N/NN-{name}.md` — N archivos
>     numerados (01, 02, ...) por Sprint, donde NN es el orden de ejecución
>     y `{name}` es kebab-case descriptivo.
>   - **Tracking cross-cutting**: `tasks/infra/pending/sprint-N/99-{name}-tracking.md`
>     (NN alto reservado para tracking, no es PR real).
>   - **Metadatos** (fecha, sprint, pr_number) van DENTRO del markdown en
>     frontmatter — NO en el filename.
>   - NO usar `preflight-NN-*`, `track-a-*`, `impl-N-*`, ni nombres con
>     fecha (`2026-MM-DD-*`).
> - **PR labels**: `sprint-3-6` (NO `track-A` ni `impl-N`).
> - **Doc headers**: `### Sprint 3-6`, `## Sprint 7-12` (NO `### Track A`).
>
> **Migración histórica**: el 2026-07-31 se hizo un sweep completo de tasks,
> BACKEND-DEPLOY.md, INFRA-PREFLIGHT-CHECKLIST.md (renombrado a
> INFRA-SPRINT-2-CHECKLIST.md) y AGENTS.md para unificar la terminología.
> Cualquier referencia residual a "Track A/B", "Impl-N", "Prod-N" o
> "preflight" debe corregirse al editar el archivo.
>
> **Excepción documentada**: si un término externo (ej: nombre de branch
> upstream, referencia en código histórico) usa la nomenclatura antigua,
> agregar entre paréntesis la equivalencia nueva SOLO en el primer comment
> del archivo. Ej: `# antes: feat/impl-2-storage-modules (ahora: feat/sprint-3-storage-modules)`.
> Después, usar solo la nueva.
>
> **Razón**: la mezcla de "Sprint", "Track", "Impl-N", "Prod-N" y
> "preflight" generaba confusión mental para el owner (@ahincho) y para
> cualquier revisor. Una sola dimensión de naming (Sprint N) elimina la
> ambigüedad y facilita grep/búsqueda.

## Prioridad de alertas de seguridad (regla dura)

> **Regla dura**: toda alerta de seguridad reportada por Dependabot, CodeQL
> o GitHub Advanced Security (GHAS / Code Scanning) tiene **prioridad P0**
> (bloqueante para merge). No se mergea un PR con alertas abiertas de estas
> herramientas.

**Workflow obligatorio al encontrar una alerta:**

1. **Clasificar** la alerta:
   - `Dependabot`: vulnerabilidad en una dependencia (npm, github-actions, terraform provider).
   - `CodeQL`: vulnerabilidad de código (SQL injection, XSS, hardcoded secrets, etc.).
   - `GHAS / Code Scanning`: SARIF subido por checkov u otra herramienta de análisis estático.
2. **Para alertas de Dependabot**: mergear el PR que Dependabot abre (auto-fix) O actualizar manualmente.
3. **Para alertas de CodeQL**: arreglar el código o suprimir inline con `// lgtm[query-id]` + justificación.
4. **Para alertas de GHAS / Code Scanning**:
   - **Real**: arreglar el código (regla `# checkov:skip=ID:reason` con justificación válida, o refactor del recurso).
   - **False positive**: dismissar con razón específica (`won't fix`, `false positive`, `used in tests`).
5. **Verificar** con `gh api /repos/{owner}/{repo}/code-scanning/alerts` o
   `gh api /repos/{owner}/{repo}/dependabot/alerts` que el count de open alerts = 0 antes de mergear.
6. **Documentar** la acción en la bitácora del PR o en un task `/tasks/infra/`.

**Anti-pattern**: dismissar alertas masivamente sin justificación, ocultar
alertas, o marcarlas como wont_fix sin documentación. Esto oculta vulnerabilidades
reales y bloquea la capacidad del equipo de auditar.

**Excepción**: alertas duplicadas o de runs anteriores (mismo recurso, mismo SHA
anterior) que ya fueron resueltas en el último push. Estas se pueden dejar
que GH las auto-resuelva al pushear el fix.

### Lección aprendida (2026-07-31): NO inventar justificaciones

**Incidente**: en el cleanup de PR #65 se dismissaron 3 alertas CKV2_AWS_5
("Ensure that Security Groups are attached to another resource") con la
siguiente razón:

> "False positive: SGs attached via aws_security_group_rule."

**Problema**: la razón es **conceptualmente incorrecta**.

- `aws_security_group_rule` = reglas de ingress/egress. **NO** adjunta el SG
  a otro recurso.
- "Attached to another resource" = referenciado en `vpc_security_group_ids`
  de `aws_instance`, `aws_db_instance`, `aws_lambda_function`,
  `aws_vpc_endpoint`, etc.
- En el código del PR #65 los SGs son **standalone** (sin consumers reales
  en el repo todavía). Los consumers vendrán en Tasks A8-A14.

**Acción correctiva aplicada**:

1. Las 3 alertas fueron **re-abiertas** (state=open) usando
   `PATCH .../alerts/$num` con `{"state": "open"}`.
2. Re-dismissadas con la razón correcta:
   > "DEFERRED: Sprint 1 solo extrajo SGs del modulo monolitico. CKV2_AWS_5
   > legitima (no consumers en este repo todavia). Attach ocurrira en Tasks
   > A8-A14 (Track A): sg-lambda a Lambdas, sg-rds a RDS, sg-endpoints a VPC
   > endpoints."

**Reglas duras derivadas**:

1. **Nunca** dismissar una alerta con una razón que no entiendas
   completamente. Si no sabes por qué checkov marca X como alerta, lee la
   regla en detalle (https://docs.checkov.io) y verifica en el código.
2. **Nunca** confundir `aws_security_group_rule` con "attached to another
   resource". Son conceptos distintos.
3. Si la alerta es legítima pero el fix está fuera de scope del PR actual,
   dismissar con razón `won't fix` + comentario explícito que indique:
   - Por qué es legítima (no es false positive).
   - Dónde está tracked el fix (Task # o PR futuro).
   - Quién es responsable.
4. **Antes** de dismissar, hacer `grep -r "<resource-name>"` en el repo
   para confirmar que NO hay consumer actual. Si lo hay, la razón es
   distinta.
5. La historia del dismissal queda registrada en GitHub para auditoría.
   Una razón incorrecta ahí es un problema de governance serio.

Referencia: política adoptada el 2026-07-31 tras cleanup de PR #65 (14 commits
+ 6 Code Scanning alerts dismissed + 1 PR fusionado con plan/dev limpio).

## Secrets y GH Env (estado actual)

- **GitHub Secrets (4, per env)**:
  - `AWS_PLAN_ROLE_ARN_DEV` / `AWS_PLAN_ROLE_ARN_PROD` — ARN del IAM role
    `spark-match-terraform-plan-{env}` (read-only, OIDC).
  - `AWS_APPLY_ROLE_ARN_DEV` / `AWS_APPLY_ROLE_ARN_PROD` — ARN del IAM role
    `spark-match-terraform-apply-{env}` (write, region-locked).
- **GitHub Variables (3, repo-scoped)**:
  - `TF_VERSION` = `1.15.7` (o la version actual validada).
  - `DEFAULT_NODE_VERSION` = `24` (org-level, no se usa directamente en infra).
  - `DEFAULT_PYTHON_VERSION` = `3.14` (org-level, no se usa directamente en infra).
- **GitHub Environments (2)**:
  - `dev` — branch policy = `dev`, sin reviewers, auto-approve=true.
  - `production` — branch policy = `main`, required reviewers = @spark-match/devops.

## Admin bypass policy

> **Regla dura** (adoptada 2026-08-01 tras PR #200 devops + PR #77/#78/#79
> del repo infra que bypasearon tflint via admin-bypass). Define cuando es
> aceptable usar `--admin` en `gh pr merge` para forzar un merge contra las
> required checks del ruleset `spark-match-default-branch-protection`.

**Admin bypass SOLO permitido cuando se cumplen TODAS estas condiciones:**

1. TODOS los required checks en SUCCESS (Plan dev, Checkov, tflint, gitleaks,
   sonar-terraform), Y
2. No hay reviewer disponible (nocturno, urgencia operativa, sin quorum de
   CODEOWNERS), Y
3. Queda documentado en la PR description + commit message con razon
   explicita (no "fix urgente" generico, sino contexto operativo concreto).

**Admin bypass NO permitido cuando:**

- Cualquier required check en FAILURE (incluyendo tflint, gitleaks,
  sonar-terraform).
- Alertas CodeQL / Dependabot / GHAS OPEN (regla dura ya existente, ver
  seccion "Prioridad de alertas de seguridad").
- Coverage gap.
- "Solo para mergear rapido" sin justificacion operativa documentada.

**Workflow al usar admin-bypass:**

1. Abrir PR normalmente.
2. Esperar a que TODOS los required checks pasen en verde.
3. Si no hay reviewer en el CODEOWNERS team disponible, documentar en la
   PR description:
   - Que se intenta admin-bypass.
   - Por que no hay reviewer (contexto operativo).
   - Que el autor del PR (@ahincho) se hace responsable.
4. `gh pr merge --admin --squash --delete-branch`.
5. El commit de merge debe llevar en el body la justificacion operativa.
6. Documentar el bypass en la bitacora de la task correspondiente
   (`tasks/infra/pending/sprint-N/`).

**Anti-pattern**: usar admin-bypass para "saltarse" checks en rojo.
Esto oculta fallas de tooling / cobertura / seguridad y bloquea la
capacidad del equipo de auditar. Si un check falla, se arregla el problema
raíz, no se bypasea.

Referencia: PR #200 (spark-match-01-devops) actualizo el ruleset 18893016
agregando tflint/gitleaks/sonar-terraform como required checks. Antes de
este PR, era posible (aunque no recomendado) admin-bypass con checks en
rojo. A partir de 2026-08-01 eso esta formalmente prohibido por esta
politica.

## Reglas duras (no negociables)

1. **Nunca** pegar AKIA / ASIA / access keys literales en archivos
   versionados. Solo referencias por nombre de perfil (`spark-match-admin`,
   `orion-admin`). Si necesitas el Key ID bajo un perfil, usa
   `aws configure get aws_access_key_id --profile <nombre>` en lugar de
   pegarlo en el codigo. **Si una key se filtra al repo por error, rotala
   inmediatamente en la consola de AWS** — el key ID viejo en `git log` es
   entonces texto muerto.

2. **Nunca** commitear `.tfstate`, `.terraform/`, ni archivos con secretos
   fuera de GH Secrets. `.gitignore` ya los excluye; respeta la convencion.

   **Excepcion**: `.terraform.lock.hcl` **SI se commitea** (uno por directorio
   con `versions.tf`) para garantizar reproducibilidad de providers en CI/CD.
   El `.gitignore` lo permite explicitamente con `!*.terraform.lock.hcl`.

3. **Reglas de branching**: PR a `dev` (rutinaria) o `main` (sync desde dev).
   Squash-only, branch borrada tras merge. No commitear directo a `dev` o
   `main`.

4. **OIDC trust policy `sub` format (GitHub Actions)**: las trust policies
   de los roles asumibles por `token.actions.githubusercontent.com`
   (spark-match-terraform-plan-{env}, spark-match-terraform-apply-{env},
   spark-match-sam-deploy-{env}, spark-match-bedrock-agentcore-deploy-{env},
   spark-match-lambda-runtime-{env}, spark-match-agentcore-runtime-{env})
   deben usar el **formato actual** del `sub` claim de OIDC tokens de GitHub
   Actions:
   ```
   repo:OWNER@USER_NUMERIC_ID/REPO@REPO_NUMERIC_ID:REF_TYPE
   ```
   El **formato clasico** sin IDs (`repo:OWNER/REPO:REF_TYPE`) puede no
   matchear — GitHub emite los IDs numericos. `StringLike` con el pattern
   completo (incluyendo `@*` wildcard para los IDs) funciona tanto para
   repos privados como publicos. El audience es siempre `sts.amazonaws.com`.
   Si se vuelve a bootstrap el OIDC en otra cuenta / repo, ajustar los IDs
   y validar con `aws sts assume-role-with-web-identity` antes de mergear.

5. **OIDC thumbprints**: el OIDC provider `token.actions.githubusercontent.com`
   tiene 2 thumbprints activos (viejo + nuevo cert de 2026). Ambos deben
   estar en `var.oidc_provider_thumbprints` durante la transicion. Solo
   remover el thumbprint viejo cuando AWS / GitHub confirme que el cert
   viejo fue reemplazado en produccion. Ver
   [`docs/adr/0001-oidc-thumbprint-rotation.md`](docs/adr/0001-oidc-thumbprint-rotation.md).

6. **Default SG vacio**: el `aws_default_security_group.default` se reescribe
   con `ingress = []` y `egress = []` para CKV2_AWS_12. Cualquier recurso
   que intente usar el default SG falla porque no hay reglas. SIEMPRE
   declarar SGs dedicados en los modulos.

7. **kebab-case en `name:` de workflows / jobs / steps**: prohibido Title
   Case, CamelCase, snake_case, ni paréntesis con espacios. Display
   names como `Apply (dev)` son un anti-pattern; usar `apply-dev`. El
   catálogo de [`spark-match-01-devops/AGENTS.md` §5.1](https://github.com/spark-match/spark-match-01-devops/blob/main/AGENTS.md)
   es la fuente de verdad. Esta convención se aplica también a `id:` de
   jobs y steps, inputs/outputs de reusables, y templates embebidas
   (`name: checkov-${{ matrix.path }}`, NO `name: checkov (${{ matrix.path }})`).

8. **Conventional Commits enforcer**: todo commit debe seguir Conventional
   Commits 1.0.0 con type-enum y scope-enum definidos en `.commitlintrc.json`.
   El enforcer corre en local (`.pre-commit-hooks/commit-msg.sh` via
   `pre-commit install`) y en CI (`.github/workflows/commitlint.yml`
   consumiendo el reusable de `01-devops`). Scope enum y regex del hook
   local deben estar sincronizados (los bats tests en
   `tests/bats/commitlint-config.bats` lo verifican). Para añadir un
   scope nuevo ver la sección "Convenciones de Commits" arriba.

9. **Release-please + sync commits**: el flujo `dev` → `main` usa merge
   commits (`chore: sync dev into main`). Estos commits NO bumpean version
   en release-please porque `chore:` no es release-trigger. Solo `feat:`
   o `fix:` (o commits con `BREAKING CHANGE:` footer) generan releases.
   Esto es por diseño, NO requiere workarounds. Ver la sección "Releases"
   arriba para el flujo completo.

## Convenciones Terraform

- **Provider**: AWS `~> 6.0` (fijo en `live/dev/versions.tf`,
  `live/prod/versions.tf`, `modules/*/versions.tf`).
- **Backend**: S3 + native lockfile (`use_lockfile = true`).
- **Tagging**: `default_tags` a nivel de provider (definido en
  `live/dev/providers.tf` y `live/prod/providers.tf`). Tags obligatorios:
  `Project=spark-match`, `Environment=<env>`, `ManagedBy=terraform`,
  `Repository=spark-match/spark-match-02-infrastructure`. NO reconstruir
  `local.common_tags` por modulo — usar el provider default.
- **Naming**: `spark-match-<componente>-<env>` para todos los recursos.
- **Validations**: usar `validation { condition = ... }` en variables
  (`project_name` kebab-case, `environment` in `["dev","staging","prod"]`).
- **Outputs**: exponer ARNs de IAM y bucket name para wiring desde otros
  repos spark-match via `github_actions_secret` (futuro).

## Convenciones de GitHub Actions YAML

Esta repo consume reusable workflows desde
[`spark-match-01-devops`](https://github.com/spark-match/spark-match-01-devops)
y también define workflows internos en `.github/workflows/`. Ambos tipos
deben seguir la convención **kebab-case** para identificadores, definida
en
[`spark-match-01-devops/AGENTS.md` §5.1](https://github.com/spark-match/spark-match-01-devops/blob/main/AGENTS.md)
(sección "Naming convention - kebab-case obligatorio").

Aplica a:

- **`name:`** de workflow (top-level), de job y de step.
- **`id:`** de job y de step.
- **Inputs / outputs** (cuando se introduzcan reusables locales).
- **Templates** embebidas en `name:`: concatenar con `-`, nunca con
  espacio. Ejemplo: `name: checkov-${{ matrix.path }}`, NO
  `name: checkov (${{ matrix.path }})`.

**Excepciones** (no kebab):

- URLs externas (`https://github.com/...`).
- Nombres de actions de terceros (`actions/checkout`,
  `aws-actions/configure-aws-credentials`).
- Nombres de eventos de GitHub (`pull_request`, `push`,
  `workflow_dispatch`).
- GH Environment names (`dev`, `production`).
- Branch names literales referenciados en scripts.

**Brand mapping** (referencias a marcas/herramientas en `name:`,
descripciones de inputs o mensajes):

| Marca | Kebab |
|---|---|
| `Terraform` | `terraform` |
| `TFLint` | `tflint` |
| `Checkov` | `checkov` |
| `CodeQL` | `codeql` |
| `SonarCloud` | `sonar-cloud` |

**Por qué**: consistencia con el catálogo de `01-devops`. Si en el futuro
esta repo introduce reusable workflows propios, ya van a kebab-case y no
hay que renombrarlos después. El renombre posterior rompe links a
workflow runs antiguos y complica búsquedas en GitHub UI.

## Convenciones de Commits (Conventional Commits 1.0.0)

> **Regla dura**: todo commit en este repo DEBE seguir Conventional Commits
> 1.0.0. El enforcer corre en **dos puntos**:
>
> 1. **Local (commit-time)**: el hook `.pre-commit-hooks/commit-msg.sh`
>    se invoca desde el pre-commit framework Python via el hook
>    `commit-msg-conventional` declarado en `.pre-commit-config.yaml`.
>    Es un script POSIX shell puro (sin Node, sin `npm install`).
>    Duplica un subset de la reglas del CI para dar feedback inmediato
>    antes de que el commit sea creado.
>
> 2. **CI (PR-time)**: el workflow `.github/workflows/commitlint.yml`
>    consume el reusable `spark-match-01-devops/.github/workflows/
>    reusable-commitlint.yml@v0.1.16`, que corre
>    `wagoid/commitlint-github-action@v6` con la config local
>    `.commitlintrc.json`. Si el hook local skipea un commit que CI
>    rechaza, los bats tests en
>    `tests/bats/commitlint-config.bats` (drift detector) lo detectan
>    antes de CI.

### Scope enum (20 infra scopes)

Los scopes permitidos viven en `.commitlintrc.json` bajo `scope-enum` Y
en `.pre-commit-hooks/commit-msg.sh` (regex). Deben estar sincronizados
(los bats tests verifican esto). Lista actual:

| Capa | Scopes |
|---|---|
| **Módulos** (componentes Terraform) | `oidc`, `networking`, `security`, `endpoints`, `kms`, `notifications`, `iam`, `observability`, `rds`, `lambda`, `budget` |
| **Capas Terraform** | `live`, `modules`, `terraform` |
| **Generales** | `ci`, `deps`, `docs`, `governance`, `scripts`, `repo` |

El scope es **opcional** (`scope-empty: 0`). Los sync commits entre
ramas usan `chore: sync dev into main` (sin scope) y son válidos.

### Tipos permitidos (10)

`feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`,
`perf`, `revert`. Heredados de `@commitlint/config-conventional`.

### Reglas de subject

- **lowercase**: sin letras mayúsculas en el subject.
- **sin punto final**: el subject NO termina con `.`.
- **header ≤ 100 chars**: validación sobre el FULL first line del commit
  (incluye el prefijo `<type>(<scope>): `), NO solo el subject.

### Exenciones

Los siguientes prefijos pasan sin validación (heredan el patrón de
01-devops):

- `Merge ...`
- `Revert "..."`
- `fixup! ...`, `squash! ...`, `amend! ...`

### Pitfall: amend local no actualiza el PR title (squash merge)

Cuando se hace `git commit --amend` localmente para corregir el subject
(scope, uppercase, etc.) antes de merge, el **PR title en GitHub NO se
actualiza automáticamente**. Si el PR se mergea con `--squash`, GitHub
usa el **PR title** como subject del squash commit — NO el commit
message local. Resultado: el commit en `main`/`dev` queda con el
subject viejo y fail commitlint post-merge.

**Fix**: tras un amend, también actualizar el PR title:

```bash
gh pr edit <num> --title "<nuevo subject>"
```

Si el merge ya ocurrió con el subject malo, hay dos opciones:

1. **Fix forward** (recomendado): nuevo PR que añade 1-2 commits con
   scope/subject válidos. `commit-depth: 2` del reusable-commitlint
   evalúa solo los últimos 2 commits — los nuevos válidos tapan el
   malo antiguo.
2. **Reset + force-push**: solo si el branch no está protegido o si
   se tiene admin bypass. Riesgo de historial inconsistente.

Lecciones aprendidas en este repo: PR #114 (scope `workflows` no
válido en 02-infra) y PR #115 (`PR` mayúscula, sujeto al rule
`subject-case: lower-case`). Ambos requirieron fix forward.

### Cómo añadir un scope nuevo

1. Editar `.commitlintrc.json` `scope-enum` (lista en `rules.scope-enum[2]`).
2. Editar `.pre-commit-hooks/commit-msg.sh` `SCOPE_RE` (regex ampliado).
3. Actualizar la tabla en este AGENTS.md.
4. Correr `bats tests/bats/commitlint-config.bats` localmente; los tests
   de drift detectan cualquier desincronización.
5. PR con `chore(governance): add <new-scope> to conventional commits scope-enum`.

### Instalación local del hook

```bash
pip install pre-commit
pre-commit install
# Si quieres verificar archivos ya existentes:
pre-commit run commit-msg-conventional --all-files
```

Si `pre-commit` no está disponible, `git commit` igual funciona pero
sin el check local — el CI actúa como red de seguridad.

### Referencia

Catálogo de CI/CD compartido: [`spark-match-01-devops/AGENTS.md`](https://github.com/spark-match/spark-match-01-devops/blob/main/AGENTS.md)
(§3 Conventional Commits, §5.1 kebab-case). Esta sección refleja la
misma convención adaptada al scope enum de infra.

## Antes del primer apply

1. Decidir cuenta AWS y region (default `us-east-1`).
2. Correr `./scripts/setup-oidc.sh` desde un workstation con AWS CLI profile
   `spark-match-admin` (o `orion-admin`).
3. Configurar 4 GitHub Secrets (2 per env) + 2 GitHub Environments.
4. Correr `./scripts/bootstrap-backend.sh` para crear el bucket de state
   (cuando se agregue).
5. `cd live/dev && terraform init && terraform plan`.

Si el primer apply falla, ver [`docs/runbook-tfstate-recovery.md`](docs/runbook-tfstate-recovery.md).

## Releases — release-please automatico

`.github/workflows/release-please.yml` se dispara en cada push a `main`
y consume el reusable compartido `spark-match-01-devops/.github/
workflows/reusable-release-please.yml@v0.1.16`. Configuracion local:

- `.github/release-please-config.json` — `release-type: simple`,
  `tag-separator: @`, `package-name: spark-match-02-infrastructure`.
- `.release-please-manifest.json` — `{ ".": "0.1.0" }` (semver actual).
- Tag format: `v0.1.0@spark-match-02-infrastructure`.

El flujo es:

1. Push a `main` dispara `release-please`.
2. release-please mira los commits desde el ultimo tag y determina el
   bump (feat → minor, fix → patch, breaking change → major).
3. Si hay bump, abre un PR `release <version>` con CHANGELOG.md
   actualizado.
4. Merge del PR → tag + GitHub Release + bump del manifest.

**Importante**: los commits `chore: sync dev into main` NO bumpean
(chore no es release-trigger). Solo `feat:` y `fix:` (o commits con
`BREAKING CHANGE:` footer) generan releases.

### Bootstrap de GitHub App secrets

El workflow requiere 2 secrets en GitHub Actions (repo or org level):

- `RELEASE_PLEASE_APP_ID` — ID del GitHub App.
- `RELEASE_PLEASE_APP_PRIVATE_KEY` — Llave privada (PEM) del App.

Estos secrets se reutilizan de la misma GitHub App que `spark-match-01-devops`
usa (mismo org owner). Si no estan configurados, el workflow falla con:

  Error: The 'client-id' (or deprecated 'app-id') input must be set to
  a non-empty string.

**Setup**:

1. Settings → Secrets and variables → Actions → New repository secret.
2. Name: `RELEASE_PLEASE_APP_ID`, Value: el ID numerico del App.
3. Name: `RELEASE_PLEASE_APP_PRIVATE_KEY`, Value: el contenido del
   archivo `.pem` (con saltos de linea, copiar literal).
4. Asegurarse que el App este instalado en el repo `spark-match-02-infrastructure`
   con permisos: Contents (write), Pull requests (write), Metadata (read).

### Sync dev → main

Este repo usa el patron `dev` → `main` con merge commits (`chore: sync dev into main`).
El workflow `release-please` dispara en cada push a `main`, así que
los sync commits entre dev y main también disparan el workflow, pero
como el sync commit es `chore:`, no se bump-ea version. Los `feat:`
y `fix:` reales (mergeados a dev primero) sí son detectados por
release-please cuando se sync-ean a main.

**Override**: si necesitas bumpear manualmente o evitar un release,
usa `[skip release]` en el footer del commit o mergea el release PR
manualmente con la version deseada.

## Cleanup de infraestructura (convencion pipeline-only)

> **Pendiente Sprint 2**: actualmente no existe `terraform-cleanup.yml`
> standalone. Cualquier cleanup se hace via `aws` CLI directo desde el
> workstation (como hicimos en el cleanup de AWS del 2026-07-28). Una vez
> que el workflow se cree (siguiendo el patron de
 `orion-infrastructure/.github/workflows/terraform-cleanup.yml`), TODOS los
   borrados de recursos deberan ir por pipeline (gating con `cleanup_token`).

## Contacto

- Owner: `@ahincho` (admin principal).
- Reviewers: `@spark-match/devops` (CODE OWNERS).
