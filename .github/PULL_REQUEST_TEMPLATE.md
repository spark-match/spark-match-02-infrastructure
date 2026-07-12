# Pull Request

## Resumen

<!-- Describa brevemente que cambia este PR y por que. -->

## Tipo de cambio

- [ ] Bugfix (cambio que arregla un issue sin breaking change)
- [ ] Nueva feature (cambio que agrega funcionalidad sin breaking change)
- [ ] Breaking change (fix o feature que causaria que funcionalidad existente no funcione como antes)
- [ ] Refactor / housekeeping (sin cambio funcional)
- [ ] Documentacion

## Alcance

- [ ] Cambios solo en `dev` (no afecta prod)
- [ ] Cambios que se aplicaran a `dev` y `prod` (requiere aprobacion de CODE OWNERS + sync a main)

## Items relacionados

<!-- Vincular a issues, ADRs u otros PRs. -->

- [ ] Issue/ADR: #
- [ ] PR relacionado en otro repo: spark-match/#

## Checklist del autor

- [ ] `terraform validate` corre sin errores en `live/dev` y `live/prod`
- [ ] `pre-commit run --all-files` corre sin errores
- [ ] `tflint` corre sin errores
- [ ] `checkov` corre y revisé los findings (justificar los aceptados)
- [ ] Documente cambios en `README.md` / `docs/IAM_ROLES.md` si aplica
- [ ] Si agregue un path nuevo al repo, lo liste en `.github/CODEOWNERS`
- [ ] Si toque politicas IAM, verifique que el bucket de tfstate del ambiente correcto esta parametrizado
- [ ] Si agregue recursos nuevos, verifique que el costo estimado es aceptable

## Checklist del reviewer

- [ ] El plan de Terraform no muestra deltas inesperados en `live/dev`
- [ ] El plan de Terraform no muestra deltas inesperados en `live/prod` (si aplica)
- [ ] Los paths nuevos tienen CODE OWNERS asignados
- [ ] No hay secretos hardcodeados (AWS keys, passwords, etc.)
- [ ] No hay `file()` sobre JSON de politicas IAM (debe ser `templatefile()`)
- [ ] Los tags `Project=spark-match` y `Environment={env}` estan presentes

## Screenshots / output relevante

<!-- Pegue el output relevante de terraform plan, checkov, etc. -->

```text
$ terraform plan -var-file=live/dev/terraform.tfvars
... (pegar resumen)
```

## Notas para el deploy

<!-- Pasos manuales necesarios, si los hay (ej. bootstrap de bucket, crear GH secret, etc.). -->
