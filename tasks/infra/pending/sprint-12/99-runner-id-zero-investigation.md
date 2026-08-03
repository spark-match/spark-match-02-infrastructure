---
sprint: 12
date: 2026-08-03
pr_number: null
status: pending-investigation
---

# Investigation: Plan (dev) falla con runner_id=0 en todos los PRs

## Resumen

`Plan (dev) / plan-dev` falla consistentemente con `runner_id: 0`, `steps_count: 0`,
duracion 1 segundo. Observado en PRs #93, #94, #95, #97, #99, #100, #101 (7 PRs
consecutivas). El check `Plan (prod) / plan-prod` no se ve afectado porque solo
corre en `workflow_dispatch` (manual), no en PRs.

## Root cause

**No es un problema de runners.** Es una regla de proteccion de GitHub Environment.

El job en `terraform-plan-dev.yml` pasa `environment: dev` al reusable
`spark-match-01-devops/.github/workflows/reusable-terraform-plan.yml@main`.
Ahi, en `reusable-terraform-plan.yml`, el job interno declara:

```yaml
jobs:
  plan:
    environment: ${{ inputs.environment-name || inputs.environment || inputs.working-directory }}
```

Esto crea un **deployment record** hacia el env `dev` cada vez que el job corre.
El env `dev` en este repo tiene `deployment_branch_policy.custom_branch_policies`
configurado asi (verificado via API `GET /environments/dev/deployment-branch-policies`):

```json
{
  "total_count": 1,
  "branch_policies": [
    { "id": 56367676, "name": "dev", "type": "branch" }
  ]
}
```

Es decir, solo el branch `dev` puede deployar al env `dev`. Cuando el job corre
desde un PR, el ref es `refs/pull/N/merge` (NO `dev`), entonces GitHub rechaza
el deployment **antes de asignar un runner** (por eso `runner_id: 0`,
`steps_count: 0`, duracion 1s).

## Evidencia

```
$ gh run view 30833494733 --repo spark-match/spark-match-02-infrastructure
JOBS
X Plan (dev) / plan-dev in 1s (ID 91752900172)

ANNOTATIONS
X Branch "refs/pull/94/merge" is not allowed to deploy to dev due to
  environment protection rules.
X The deployment was rejected or didn't satisfy other protection rules.
```

```
$ gh api repos/spark-match/spark-match-02-infrastructure/environments/dev
{
  "name": "dev",
  "can_admins_bypass": true,
  "protection_rules": [{"type": "branch_policy"}],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
```

`can_admins_bypass: true` solo aplica a workflows manuales disparados por un
admin desde la UI. Para runs automaticos (`pull_request`), el runner protection
rule se sigue aplicando.

## Workaround aplicado (temporal)

`gh pr merge --admin --squash --body "..."` documenta en cada PR que el fail es
infraestructura, no codigo. No es ideal porque requiere justificacion en cada
PR y oculta fallas legitimas si occuren.

## Fix propuesto (pendiente decision)

### Opcion A: Separar env para PR plans (recomendada)

Crear env `dev-plan` (sin branch policy) y mover el secret `AWS_PLAN_ROLE_ARN`
ahi. Cambiar `terraform-plan-dev.yml` para pasar `environment: dev-plan` al
reusable. Mantener env `dev` (con branch policy) solo para applies.

Pros:
- Cero cambios en 01-devops.
- PR plans corren sin friccion.
- Apply sigue protegido (solo `dev` branch puede apply).

Contras:
- Duplica IAM role reference (mismo role, 2 envs). Aunque solo movemos el
  secret, no duplicamos el role.
- Naming inconsistency: hay envs `dev`, `production` para applies + envs
  `dev-plan`, `production-plan` para plans.

Implementacion:
1. `gh api -X PUT repos/spark-match/spark-match-02-infrastructure/environments/dev-plan`
   con body sin `deployment_branch_policy`.
2. Mover secret `AWS_PLAN_ROLE_ARN` de env `dev` a env `dev-plan` (via
   `gh api` con SealedBox encryption de la libsodium).
3. Editar `.github/workflows/terraform-plan-dev.yml` linea ~44:
   `environment: dev` -> `environment: dev-plan`.

### Opcion B: Mover secret a repo-wide (NO recomendado)

Promover `AWS_PLAN_ROLE_ARN` a repo-level secret. Plans corren sin env binding.

Pros: trivial.

Contras: pierde env-scoped access control. Si en el futuro hay plan roles
distintos por env, ya no hay donde diferenciarlos. Tamien cualquier otro
workflow tendria acceso.

### Opcion C: Modificar reusable en 01-devops

Cambiar `reusable-terraform-plan.yml` para que el job interno NO bind a env
(quitar la linea `environment: ${{ ... }}` y dejar que el caller lo maneje).

Pros: alinea el reusable con el patron de "el caller decide".

Contras: requiere PR a 01-devops. Fuera del scope de 02-infrastructure.

## Decision

Pendiente. El usuario decidio investigar antes de aplicar fix. Mientras tanto
se sigue con admin-bypass + documentacion en cada PR.

## Refs

- API: `GET /repos/{owner}/{repo}/environments/{name}`
- API: `GET /repos/{owner}/{repo}/environments/{name}/deployment-branch-policies`
- AGENTS.md seccion "Reglas duras" (sin cambios requeridos por este fix).
- 01-devops `reusable-terraform-plan.yml` line ~138 (job `plan.environment`).