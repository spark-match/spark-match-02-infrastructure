# Lecciones aprendidas — Conventional Commits + admin-bypass

Este documento registra los **incidentes reales** que hemos tenido en este
repo con conventional commits enforcement y los workflows que los validan,
para que el proximo dev que toque un workflow de sync / admin-bypass no caiga
en los mismos pits.

## Caso 2026-08-04: PR title con mayusculas se convirtio en squash commit subject

### Que paso

PR #139 (`chore: remove tmp-trigger.txt from sync PR #137`) se abrio para
limpiar un archivo de ruido introducido por error en el sync #137. El PR
title contenia `PR` en mayusculas. El repo tiene
`use_squash_pr_title_as_default=true` y `squash_merge_commit_message=PR_BODY`,
asi que el squash-merge uso el PR title literal como subject del commit en
`main`:

```
5486da8 chore: remove tmp-trigger.txt from sync PR #137 (#139)
```

El commitlint workflow (`.github/workflows/commitlint.yml`, consuming el
reusable `spark-match-01-devops/.github/workflows/reusable-commitlint.yml`)
falla con:

```
✖   subject must be lower-case [subject-case]
⚠   footer must have leading blank line [footer-leading-blank]
```

### Por que esto importa

- El ruleset `spark-match-default-branch-protection` (ID 18893016) tiene
  `lint-commits / commitlint` como required check (con
  `strict_required_status_checks_policy=true`).
- En PRs contra `main`, esto hubiera bloqueado el merge.
- En push directo a `main` (que es lo que pasa al mergear un PR via web UI
  o `gh pr merge --squash`), el commit ya esta en `main` antes de que el
  workflow termine, y el workflow falla retroactivamente sin bloquear nada.
- El historial queda con un commit que falla la regla, y cualquier agente o
  humano que intente reproducir ese workflow en CI vera el fail.

### Regla derivada

**Los PR titles de sync / cleanup / chore NUNCA deben tener letras
mayusculas** mas alla de la primera letra del subject. En particular:

- `PR` (abreviatura de "Pull Request") -> usar `pr` o re-frasear
  (ej: `chore: remove tmp-trigger.txt from sync pr 137`).
- Siglas (`AWS`, `OIDC`, `S3`, `CI`, `CD`, etc.) -> usar la version lowercase
  o re-frasear (ej: `feat(iam): add oidc github trust policy` en lugar de
  `feat(iam): add OIDC GitHub trust policy`).
- Codigos de issue (`#137`) -> OK, son numericos.
- Codigos de release (`v1.0.0`) -> OK, son numericos precedidos de `v`.

Esto esta alineado con `.commitlintrc.json` (regla `subject-case` heredada de
`@commitlint/config-conventional`).

### Workaround aplicado

Fix-forward con un nuevo commit de scope `chore(governance)` cuyo subject
cumpli `subject-case: lower-case`. La regla `commit-depth: 2` del
reusable-commitlint evalua solo los ultimos 2 commits del PR, asi que el
commit bueno tapa el malo en el siguiente push a main.

No se hizo `git commit --amend` retroactivo porque el commit `5486da8` ya
esta publicado en `main` y en `origin/main`; un amend requeria force-push
a `main`, que el ruleset `required_linear_history` + `non_fast_forward`
bloquea.

### Validacion del fix-forward

- Antes: `git log origin/main` -> el commit `5486da8` falla commitlint en CI.
- Despues (post-merge del fix-forward): `git log origin/main` -> el commit
  bueno sigue al `5486da8`, y `commit-depth: 2` evalua los ultimos 2 commits
  del PR (incluye el bueno), por lo que el workflow pasa.

### Referencia

AGENTS.md seccion "Convenciones de Commits > Pitfall: amend local no actualiza
el PR title (squash merge)". El riesgo fue conocido pero subestime el impacto
en el PR title del cleanup; la proxima vez que abra un PR de cleanup, usare
`gh pr edit <num> --title "<subject en lowercase>"` despues de crearlo y
antes de mergear.