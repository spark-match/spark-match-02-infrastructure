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
git checkout -b feat/{name}   # o fix/{name} / chore/{name}
git push -u origin feat/{name}
# crear PRs incrementales desde esta branch contra dev
```

### 2. PR a `dev` (work integration)

- PR target: `dev`.
- Squash merge (regla del repo).
- Branch deletion on merge (regla del repo).
- En este momento `dev` ya contiene el cambio, pero `main` no.

### 3. Sync a `main` (release a produccion)

- PR target: `main`.
- Squash merge con titulo `chore: sync dev into main (<resumen>)`.
- Branch deletion on merge.

**Cuando promover dev -> main** (criterios, en orden de precedencia):

| Trigger | Categoria | Ejemplo |
|---|---|---|
| Conjunto de trabajo cerrado y QA aprobado | **Madurez** | Feature/modulo completo, tests OK |
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
> que el owner del repo o el desarrollo indique lo contrario.

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

### Workflow automatizado (futuro)

Pendiente: crear workflow `.github/workflows/check-sync.yml` que corra en
cron semanal (`schedule: cron: '0 0 * * 0'`) y falle si el `git diff`
NO esta vacio. Notifica via Slack o abre issue automatica.

## Naming de branches y coordinación cross-repo (regla operacional)

> **Regla operacional** (vigente desde 2026-08-04): este repo adoptó el
> 2026-07-31 una terminología unificada "Sprint N" (para branches, tasks,
> labels y doc headers) y un sistema de task files en
> `tasks/infra/pending/sprint-N/`. Ambas convenciones se **revirtieron 4
> días después** por no aportar valor operacional frente al ritmo real de
> trabajo. PRs y commits ya mergeados que mencionan "Sprint N" NO se
> reescriben (son historia inmutable); solo el trabajo nuevo sigue la
> convención vigente.

**Convención vigente:**

- **Branch names**: descriptivos, kebab-case, **sin número de sprint ni
  código de track/fase**. `feat/{name}`, `fix/{name}`, `chore/{name}`.
  Ejemplo: `feat/rds-postgres-module` (NO `feat/sprint-13-rds-postgres-module`,
  NO `feat/track-a-rds-postgres-module`, NO `feat/a6-rds-postgres-module`).
- **Coordinación cross-repo**: cuando un cambio en este repo requiere
  trabajo de otro agente/equipo (ej: `01-devops` para un reusable workflow,
  `03-backend` para wiring de un output) se comunica **directamente en la
  conversación/chat** con el responsable. NO se crea un archivo markdown de
  task en `tasks/infra/` para trackear el pedido.
- **PR labels y doc headers**: descriptivos por tema (`iac`, `governance`,
  `security`, etc.), sin número de sprint ni código de fase.

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
6. **Documentar** la acción en la bitácora del PR.

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

### Required checks actuales del ruleset 18893016 (post-2026-08-04)

El ruleset tiene **21 required checks** distribuidos en 4 grupos:

- **CI base (7)**: `plan-dev / plan-`, `tflint / tflint-`, `gitleaks / gitleaks-`,
  `sonar-terraform / sonar-terraform-dev`, `terraform-validate / terraform-validate-`,
  `quality / bats`, `lint-commits / commitlint`.
- **Checkov matrix (14)**: `checkov-live/dev`, `checkov-live/prod`, y 12
  `checkov-modules/<module>` (networking, security-groups, endpoints,
  oidc-github, kms, notifications, storage-sam-artifacts, secrets-bootstrap,
  eventbridge-bus, dynamodb-idempotency, ssm-bootstrap, rds-postgres).

**Nota 2026-08-04**: el check top-level derivado `Checkov` (Code Scanning
check que se genera automaticamente cuando el SARIF de checkov sube
resultados) **fue removido** del required check del ruleset en esta fecha.
Razon: en sync PRs con diff amplio contra `main` (caso PR #137, 53 archivos),
Code Scanning re-reportaba alertas pre-existentes del codigo de `dev` como
"new in PR diff" -- side-effect estructural del `git merge --squash` que no
representa alertas reales. Los 14 matrix jobs de checkov siguen siendo
required, asi que el escaneo real NO se pierde, solo se elimina el check
derivado que re-reports alertas pre-existentes.

**Admin bypass SOLO permitido cuando se cumplen TODAS estas condiciones:**

1. TODOS los 21 required checks en SUCCESS (los 7 CI base + los 14 checkov
   matrix jobs; el top-level `Checkov` ya NO es required post-2026-08-04), Y
2. No hay reviewer disponible (nocturno, urgencia operativa, sin quorum de
   CODEOWNERS), Y
3. Queda documentado en la PR description + commit message con razon
   explicita (no "fix urgente" generico, sino contexto operativo concreto).

**Admin bypass NO permitido cuando:**

- Cualquier required check en FAILURE (incluyendo tflint, gitleaks,
  sonar-terraform, o cualquiera de los 14 checkov matrix jobs).
- Alertas CodeQL / Dependabot / GHAS OPEN (regla dura ya existente, ver
  seccion "Prioridad de alertas de seguridad").
- Coverage gap.
- "Solo para mergear rapido" sin justificacion operativa documentada.

### Patron especifico para sync PRs (chore: sync dev into main)

Los sync PRs que promueven trabajo cerrado de `dev` a `main` tienen una
particularidad: a menudo divergen del ruleset por **falta de reviewer**
(@spark-match/devops es team-of-1, sin quorum para review normal), no por
checks en rojo. El admin-bypass es aceptable en este caso siguiendo la
politica general, con dos consideraciones adicionales:

1. **Documentar bypass + sync process**: en la PR description incluir:
   - Lista explicita de PRs promovidos desde `dev`.
   - Lista de archivos / lineas modificadas (`git diff --stat origin/main origin/dev`).
   - Estado de las alertas CodeQL/Dependabot (verificado via `gh api`).
   - Estado de `live/dev` aplicado (verificado via `terraform plan` 0 drift).
   - Estado de `live/prod` (code only, no aplicado).
2. **Verificar contenido del squash** antes del merge: `git diff --cached origin/dev`
   debe ser vacio (o solo contener el drift intencional documentado). Si hay
   drift no intencional, NO hacer bypass, resolver primero.

**Workflow al usar admin-bypass (general, valido para sync y feature PRs):**

1. Abrir PR normalmente.
2. Esperar a que TODOS los required checks pasen en verde.
3. Si no hay reviewer en el CODEOWNERS team disponible, documentar en la
   PR description:
   - Que se intenta admin-bypass.
   - Por que no hay reviewer (contexto operativo).
   - Que el autor del PR (@ahincho) se hace responsable.
4. `gh pr merge --admin --squash --delete-branch`.
5. El commit de merge debe llevar en el body la justificacion operativa.
6. Documentar el bypass en la descripcion del PR o en el commit de merge.

**Anti-pattern**: usar admin-bypass para "saltarse" checks en rojo.
Esto oculta fallas de tooling / cobertura / seguridad y bloquea la
capacidad del equipo de auditar. Si un check falla, se arregla el problema
raíz, no se bypasea.

**Leccion historica (2026-08-04)**: 3 sync PRs consecutivos (#137, #139,
#141) requirieron admin-bypass en una sola sesion. Patrones observados:

- PR #137: admin-bypass por Checkov top-level FAILURE (side-effect Code
  Scanning en diff amplio). **Resuelto post-hoc** quitando `Checkov` del
  ruleset (esta seccion).
- PR #139: admin-bypass por Checkov top-level + PR title con mayusculas
  (`PR #137` literal) fallo `subject-case: lower-case` post-push a main.
  **Resuelto** via cleanup PR + fix-forward PR #140 (commit valido tapa
  el malo en `commit-depth: 2`). Llesson documented in
  `docs/lessons-learned-conventional-commits.md`.
- PR #141: admin-bypass por falta de reviewer (Checkov top-level ya no
  era required post-fix). Tamaño del diff (2 archivos docs) no justificaba
  dividirlo.

Conclusion: tras quitar `Checkov` del ruleset, los futuros sync PRs solo
requeriran admin-bypass por **falta de reviewer**, no por checks en rojo.
Esto reduce la superficie de admin-bypass significativamente.

Referencia: PR #200 (spark-match-01-devops) actualizo el ruleset 18893016
agregando tflint/gitleaks/sonar-terraform como required checks. Antes de
este PR, era posible (aunque no recomendado) admin-bypass con checks en
rojo. A partir de 2026-08-01 eso esta formalmente prohibido por esta
politica.

## Follow-ups conocidos (fuera de scope actual)

> **Estado**: items identificados durante el trabajo de governance
> (Fase 2, PRs #128-#143) que requieren accion futura. NO son
> bloqueantes para syncs `dev -> main` ni para aplicar prod, pero deben
> ser trackeados para evitar que se olviden.

### FU-1: 7 checkov findings pre-existentes compartidos dev/prod (low)

Identificados durante la sesion de governance del 2026-08-04. Son
alertas que **ambos** environments (dev y prod) heredan de modulos
compartidos y NO son false positives -- son riesgos reales que requieren
cambios cross-module:

1. `CKV2_AWS_61` -- `lifecycle_rule` en `modules/storage-sam-artifacts/main.tf`
   no tiene `abort_incomplete_multipart_upload_days`. Mitigacion:
   anadir bloque `abort_incomplete_multipart_upload` al lifecycle rule
   (aplica a `sam_artifacts` y `access_logs`, 2 findings totales).
2. `CKV_AWS_354` -- `aws_db_instance.performance_insights_enabled = false`
   en `modules/rds-postgres/variables.tf`. Mitigacion: ya corregido
   parcialmente en PR #136 (prod usa `performance_insights_enabled = true`
   + `performance_insights_kms_key_id = module.kms.kms_key_arn`). Dev
   sigue con default `false` por diseno (Free Tier guardrail). NO es
   accionable mientras el guardrail aplique.
3. `CKV2_AWS_29` -- `enable_log_file_validation = false` en
   `modules/rds-postgres/main.tf` (RDS log exports). Mitigacion: agregar
   variable `rds_enable_log_file_validation` con default `true` en
   prod, `false` en dev (costo CloudWatch Logs).
4. `CKV_AWS_161` -- KMS-based encryption en secrets con auto-rotation
   en `modules/secrets-bootstrap/main.tf`. Mitigacion: anadir
   `rotation_rules { automatically_after_days = 90 }` + un
   `aws_secretsmanager_secret_rotation` resource que invoque una Lambda
   de rotacion. Scope: cross-module (necesita Lambda de rotacion).
5. `CKV_AWS_149` -- Similar a #4, secretos de `modules/rds-postgres`
   sin rotation. Misma mitigacion que #4.
6. `CKV_AWS_21` -- `versioning` no habilitado en
   `modules/storage-sam-artifacts/access_logs`. Mitigacion: versionar
   el bucket de access logs (costo extra, baja prioridad).
7. `CKV_AWS_19` -- `access_logs` bucket no cifrado con KMS. Mitigacion:
   cambiar SSE-S3 a SSE-KMS usando la CMK del proyecto (requiere que
   el servicio de log delivery tenga permisos sobre la CMK).

**Decision recomendada**: items #1, #3 son low effort (1-2 lineas de
codigo cada uno), pueden resolverse en un PR dedicado. Items #4, #5
requieren Lambda de rotacion -- scope mayor, mejor en una sesion
dedicada. Items #6, #7 son low value vs cost.

### FU-2: rds_backup_retention_period_days=0 en prod (medium)

**Decision humana explicita** adoptada en PR #136. La cuenta AWS
`681526276858` tiene guardrails de "Free Tier account" (no confundir con
free-tier clasico) que rechazan `CreateDBInstance` con
`FreeTierRestrictionError` si `backup_retention_period > 0`. Prod usa
LA MISMA cuenta AWS que dev, por lo que el mismo guardrail aplica.

**Riesgo operacional**: sin backups automaticos de RDS en prod. Si la
instancia falla, no hay punto de recuperacion automatico (solo el
snapshot final al borrarla).

**Opciones para resolverlo**:
- Upgrade de la cuenta a "Paid" (no "Free Tier account" sino tier
  estandar): AWS Support case. Probablemente toma dias y requiere
  verificacion de billing info.
- Cuenta AWS dedicada para prod: costoso (requiere reorganizar toda la
  infraestructura multi-env). Fuera de scope.
- Aceptar el riesgo y aplicar con retention=0: opcion actual.

**Tracking**: no requiere codigo. Documentar en `live/prod/variables.tf`
(comentario existente es suficiente) y revisar antes del primer apply
real a prod.

### FU-3: git housekeeping oddity del branch feat/wire-live-prod-modules (low)

Observado durante la sesion: el branch local `feat/wire-live-prod-modules`
desaparecio del working tree despues del merge del PR #136 sin un
`git branch -D` explicito por mi parte. Posibles causas:
- Limpieza automatica por el IDE / extension de Git
- Limpieza por otro agente / sesion paralela que opera en el mismo repo
- Reset del working tree por `git checkout` inadvertido

**Impacto**: cero. El branch ya estaba mergeado a dev (su trabajo vive
en el commit `0cc5601`) y el remote fue borrado via
`--delete-branch` automatico del PR. La rama local desaparecida no
afecta al historial ni al estado de `dev`/`main`.

**Accion recomendada**: ninguna. Documentado solo para consciencia.

### FU-4: bootstrap del role `spark-match-terraform-apply-dev` requiere scope IAM ampliado (medium)

**Incidente (2026-08-04)**: durante el primer apply dev de `modules/frontend-hosting`,
el OIDC assume role funciono pero `terraform plan` fallo con `AccessDenied` en
multiples servicios:

- `s3:GetLifecycleConfiguration`, `s3:GetBucketPolicy`, `s3:GetBucketLogging`
  sobre `spark-match-sam-artifacts-dev-access-logs` y `spark-match-sam-artifacts-dev`
  (storage-sam-artifacts).
- `events:DescribeEventBus` sobre `spark-match-events-dev` (eventbridge-bus).
- `SNS:GetTopicAttributes` sobre `spark-match-budget-alerts` (notifications).
- `iam:ListOpenIDConnectProviders` sobre `arn:aws:iam::681526276858:oidc-provider/*`
  (oidc-github).
- `cloudfront:CreateDistribution`, `cloudfront:CreateOriginAccessControl`,
  `cloudfront:CreateInvalidation` (frontend-hosting).

**Causa raiz**: la policy inline `ApplyPolicy` del role
`spark-match-terraform-apply-dev` (creada durante el bootstrap inicial de la
cuenta, antes de que los modulos `frontend-hosting` y `oidc-frontend`
existieran) solo permitia acciones S3 sobre `arn:aws:s3:::spark-match-tfstate-dev`.
No anticipaba que Terraform aplicaria refresh sobre otros buckets `spark-match-*-dev*`
y tampoco incluia CloudFront, SNS, EventBridge, IAM read ni Budgets read.

**Fix aplicado manualmente** (via `boto3.put_role_policy`, NO via Terraform):
la policy `ApplyPolicy` ahora tiene **18 statements** vs los 8 originales.
Nuevos statements: `S3ObjectManagementDev`, `CloudFrontManagementDev`,
`EventBridgeManagementDev`, `SNSManagementDev`, `IAMReadForOIDCAndRoles`,
`BudgetsReadDev`, `SSMReadDev`, `SecretsManagerReadDev`, `DynamoDBManagementDev`,
`RDSReadDev`. `S3BucketManagementDev` expandido a 6 buckets dev explicitos
(`tfstate`, `sam-artifacts`, `sam-artifacts-access-logs`, `frontend`,
`frontend-access-logs`, `rag-documents`).

**Estado actual**: el apply dev completo (17 recursos nuevos) **funciono**.
Los outputs de `live/dev/outputs.tf::frontend_*` ya estan consumidos por
`spark-match-04-frontend` (3 secrets set en env `development`).

**Trabajo pendiente** (no bloqueante, pero importante para evitar drift silencioso):

1. **Migrar la policy `ApplyPolicy` a un modulo Terraform** (`modules/iam-terraform-roles` o
   similar) que cree/actualice el role via `aws_iam_role` + `aws_iam_role_policy`. Asi
   cualquier drift del scope IAM queda visible en `terraform plan` antes de CI.
   **Razon para NO hacerlo ahora**: el role actualmente NO es 100% Terraform-managed
   (fue bootstrapped manualmente). El primer apply de un modulo que asuma
   ownership del role haria drift destroy/recreate del role, lo cual rompe
   workflows en vuelo. Plan: hacer el modulo, hacer un `terraform import` del
   role existente, y migrar la policy inline a una `aws_iam_policy_document`
   data source. Sesion dedicada.

2. **Misma expansion para `spark-match-terraform-apply-prod`** cuando se haga
   el primer apply a prod (agregar los buckets `spark-match-*-prod*` al scope S3).
   Por ahora prod esta en code-only, no aplicado.

3. **Pitfall**: la edicion manual via PowerShell + awscli (`aws iam put-role-policy
   --policy-document file://...`) FALLA con `MalformedPolicyDocument` aunque el
   JSON sea valido. Causa: el archivo JSON tiene BOM UTF-8 al inicio, lo cual
   AWS IAM rechaza. Workaround usado: Python con `boto3.put_role_policy(PolicyDocument=json.dumps(...))`.
   Si vuelves a editar IAM policies localmente, usa Python, no awscli+PS.

**Referencia**: PRs #151 (caller fix) y #152 (frontend-hosting fixes)
del repo `spark-match-02-infrastructure`. Apply exitoso verificado en
run `30938746947` y en ejecucion local posterior con `terraform apply`.

## Reglas duras (no negociables)

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

### Scope enum (26 infra scopes)

Los scopes permitidos viven en `.commitlintrc.json` bajo `scope-enum` Y
en `.pre-commit-hooks/commit-msg.sh` (regex). Deben estar sincronizados
(los bats tests verifican esto). Lista actual:

| Capa | Scopes |
|---|---|
| **Módulos** (componentes Terraform) | `oidc`, `networking`, `security`, `endpoints`, `kms`, `notifications`, `iam`, `observability`, `rds`, `lambda`, `budget`, `storage`, `secrets`, `events`, `dynamodb`, `ssm`, `frontend` |
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

### Regla de capitalización: siglas y abreviaturas

El rule `subject-case: lower-case` (heredado de `@commitlint/config-conventional`)
es case-sensitive y evalua TODO el subject. **Las siglas y abreviaturas
deben ir en lowercase** en PR titles y commit subjects:

- `PR` (Pull Request) -> `pr` o re-frasear (`sync pr 137` en vez de `sync PR 137`).
- `AWS` -> `aws` o re-frasear (`feat(iam): add aws oidc trust policy`).
- `OIDC`, `S3`, `CI`, `CD`, `ECR`, `RDS`, `VPC`, `IAM`, `KMS`, `SNS`, `SQS`,
  `API`, `URL`, `ARN`, `JSON`, `YAML`, `JIT`, `TTL`, `JWT` -> todos lowercase.
- `#<num>` (issue/PR number) -> OK, son numericos.
- `v<semver>` (release tag) -> OK, son numericos precedidos de `v`.

**Ejemplos validos**:
- `chore: sync dev into main (fix-forward for cleanup of pr 139)`
- `feat(iam): add aws oidc trust policy for github actions`
- `fix(rds): encrypt performance insights with project cmk`

**Ejemplos invalidos** (rompen `subject-case`):
- `chore: sync dev into main (fix-forward for cleanup of PR 139)` <- PR mayuscula
- `feat(iam): add AWS OIDC trust policy for GitHub Actions` <- siglas mayuscula
- `fix(rds): encrypt Performance Insights with project CMK` <- palabras mayuscula

Si el PR title tiene mayusculas incorrectas, **NO** abrir el PR asi. Editarlo
antes de abrir:

```bash
gh pr create --title "..."  # si usamos Ctrl+C, no crearlo
gh pr edit <num> --title "<subject en lowercase>"
```

Si ya se abrio y todavia no se mergeo, editar antes de mergear.
Si ya se mergeo (caso PR #139), fix-forward con un nuevo commit valido.

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

> **Pendiente**: actualmente no existe `terraform-cleanup.yml`
> standalone. Cualquier cleanup se hace via `aws` CLI directo desde el
> workstation (como hicimos en el cleanup de AWS del 2026-07-28). Una vez
> que el workflow se cree (siguiendo el patron de
 `orion-infrastructure/.github/workflows/terraform-cleanup.yml`), TODOS los
   borrados de recursos deberan ir por pipeline (gating con `cleanup_token`).

## Contacto

- Owner: `@ahincho` (admin principal).
- Reviewers: `@spark-match/devops` (CODE OWNERS).
