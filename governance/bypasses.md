# 🛡️ Governance — Bypasses de Branch Protection

> Este registro documenta todos los **bypasses admin** realizados sobre la
> branch protection de este repo (cuando un PR se mergea sin cumplir
> estrictamente la política de aprobación). Cada entrada incluye causa,
> procedimiento ejecutado, SHA del merge, y rollback plan.
>
> **Política**: la branch protection existe por seguridad. Un bypass debe ser
> la excepción, no la regla. Si el patrón se repite (>3 bypasses por misma
> causa), abrir un issue o ticket para resolver la causa raíz.

---

## Causa raíz (transversal a todos los bypasses)

`@spark-match/devops` tiene **2 miembros** (`dbarretol`, `ahincho`). El autor
del PR no puede aprobar su propio PR (regla nativa de GitHub). Si el otro
miembro no está disponible, **no hay revisor posible** y el PR queda
bloqueado indefinidamente.

**Solución de fondo (pendiente)**: agregar 1-2 personas más a
`@spark-match/devops` para tener revisores disponibles. Ver
`D:\UNI\Spark\README.md` lección #3.

---

## Bypass #1 — PR #8 (feat/multi-env-and-n-env-pipelines)

| Campo | Valor |
|---|---|
| **Fecha** | 2026-07-12 15:57 UTC |
| **PR** | [#8](https://github.com/spark-match/spark-match-02-infrastructure/pull/8) |
| **Título** | feat: multi-environment support with N-env aware terraform pipelines |
| **Autor** | ahincho |
| **Merge commit** | `98b20d64b668a5ed8f967b27d038727b79748be0` (squash) |
| **Razón** | Múltiples reviewers no disponibles. `@spark-match/devops` solo tiene 2 miembros (dbarretol, ahincho); autor es ahincho; el otro miembro no aprueba. El PR tenía 19h en estado BLOCKED, CI `Plan (dev) / Plan (dev)` SUCCESS. |
| **Aprobado por** | ahincho (admin override, único admin disponible) |
| **Riesgo** | Medio: PR grande (46 archivos, +3188/-772 líneas), toca módulos de seguridad y networking. Mitigado por: CI SUCCESS, code review parcial previo de Fabi (product-owners) en sesión anterior, contenido completamente revisado por el autor. |
| **Pre-bypass snapshot** | `D:\UNI\Spark\backup-2026-07-12-pre-bypass.md` |
| **Restauración si falla** | `git reset --hard a0ea8d2f085886a3c01cb36a0857dbf30ec8f482` desde local + `git push --force-with-lease origin dev` |

### Procedimiento ejecutado

1. Snapshot completo de SHAs y branch protection (ver archivo de backup).
2. Verificación de CI: `Plan (dev) / Plan (dev)` SUCCESS en run `29198730377`.
3. `gh pr merge 8 --admin --squash --repo spark-match/spark-match-02-infrastructure`
4. Verificación post-merge: PR state = MERGED, dev SHA = `98b20d64`.
5. Branch protection NO se modificó (admin override del flag `--admin` bypasea
   la aprobación requerida sin relajar la config).

---

## Bypass #2 — PR #9 (fix/iam-policies-per-environment)

| Campo | Valor |
|---|---|
| **Fecha** | 2026-07-12 15:59 UTC |
| **PR** | [#9](https://github.com/spark-match/spark-match-02-infrastructure/pull/9) |
| **Título** | fix(iam): isolate policies per environment via templatefile() |
| **Autor** | ahincho |
| **Merge commit** | `7daef11a0557bda5b9f363b038b3d63002d0e3ea` (squash) |
| **Razón** | Misma que bypass #1. PR #9 era branch-hijo de PR #8, ambos con la misma falta de reviewers disponibles. PR #9 tenía 16h en estado BLOCKED, CI `Plan (dev) / Plan (dev)` SUCCESS. |
| **Aprobado por** | ahincho (admin override) |
| **Riesgo** | Bajo: PR pequeño, aislado a 4 archivos JSON de policies IAM + módulo security + un script generador. Resuelve hallazgos críticos de seguridad (SEC-01, SEC-02, SEC-03 del IMPROVEMENTS.md). |
| **Pre-bypass snapshot** | `D:\UNI\Spark\backup-2026-07-12-pre-bypass.md` |
| **Restauración si falla** | `git reset --hard 98b20d64b668a5ed8f967b27d038727b79748be0` desde local |

### Procedimiento ejecutado

1. PR #9 estaba basado en `feat/multi-env-and-n-env-pipelines` (PR #8). Tras
   merge de #8, PR #9 quedaba CONFLICTING (sus cambios reorganizaban
   `docs/policies/` que PR #8 recién había agregado).
2. Cherry-pick del único commit propio de PR #9 (`a7186c0`) sobre el nuevo
   `origin/dev` (post-#8):
   ```bash
   git fetch origin
   git checkout fix/iam-policies-per-environment
   git reset --hard origin/dev
   git cherry-pick a7186c0f1057cd5f049c65d57881516e689f9e34
   git push --force-with-lease origin fix/iam-policies-per-environment
   ```
   Nuevo head: `8409c0f`. PR #9 ahora MERGEABLE.
3. CI re-triggered automáticamente. `Plan (dev) / Plan (dev)` SUCCESS.
4. `gh pr merge 9 --admin --squash --repo spark-match/spark-match-02-infrastructure`
5. Verificación post-merge: PR state = MERGED, dev SHA = `7daef11`.

---

## Patrón observado (siguiente bypass si pasa de nuevo)

Si en este repo se cuentan **3+ bypasses por la misma causa** (reviewers no
disponibles), abrir issue con label `governance/bypass-spam` y título
"[GOVERNANCE] Code owner unavailability causing repeated admin bypasses" para
abordar la causa raíz:

1. Agregar miembros al team CODE OWNER (`@spark-match/devops`).
2. Migrar a Rulesets a nivel organización (sección #7 del README general).
3. Restructurar `CODEOWNERS` de `02-infrastructure` (GOV-01 en
   `D:\UNI\Spark\IMPROVEMENTS.md`) para evitar acumulación de reviewers por
   paths sensibles.

## Referencias cruzadas

- `01-devops/governance/bypasses.md`: bypasses anteriores en repo hermano
  (PRs #7, #8, #9, #10) con la misma causa raíz.
- `D:\UNI\Spark\IMPROVEMENTS.md`: lista completa de hallazgos y plan de mejoras.
- `D:\UNI\Spark\README.md`: lección #3 sobre CODE OWNER de 2+ personas.
- `D:\UNI\Spark\backup-2026-07-12-pre-bypass.md`: snapshot pre-bypass de hoy.