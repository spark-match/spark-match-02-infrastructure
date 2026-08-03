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

## Antes del primer apply

1. Decidir cuenta AWS y region (default `us-east-1`).
2. Correr `./scripts/setup-oidc.sh` desde un workstation con AWS CLI profile
   `spark-match-admin` (o `orion-admin`).
3. Configurar 4 GitHub Secrets (2 per env) + 2 GitHub Environments.
4. Correr `./scripts/bootstrap-backend.sh` para crear el bucket de state
   (cuando se agregue).
5. `cd live/dev && terraform init && terraform plan`.

Si el primer apply falla, ver [`docs/runbook-tfstate-recovery.md`](docs/runbook-tfstate-recovery.md).

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
