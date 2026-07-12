# Decisiones de arquitectura - 2026-07

> Documento vivo. Captura las decisiones tomadas sobre items C1 y C16 del
> `IMPROVEMENTS.md` (Fase C, items diferidos).

## C1: Encriptacion del bucket de tfstate (SSE-S3 vs SSE-KMS)

**Decision (2026-07): Mantener SSE-S3 con AES256 (default), NO migrar a SSE-KMS.**

### Estado actual

Verificado via AWS CLI el 2026-07-12:

```bash
$ aws s3api get-bucket-encryption --bucket spark-match-tfstate-prod
{
  "SSEAlgorithm": "AES256"
}

$ aws s3api get-bucket-encryption --bucket spark-match-tfstate-dev
{
  "SSEAlgorithm": "AES256"
}
```

Ambos buckets usan AES256 (SSE-S3 con claves administradas por AWS, no customer managed).

### Trade-off considerado

**Opcion A: SSE-S3 con AES256 (estado actual)**

- (+) Cero costo adicional. SSE-S3 viene gratis.
- (+) Sin dependencia de CMK. El bucket se puede crear via `bootstrap-backend.sh` SIN Terraform.
- (+) AES256 es FIPS 140-2 compliant. Suficiente para la mayoria de compliance (incluyendo GDPR, HIPAA).
- (-) El bucket se cifra con una clave que AWS controla. Si un atacante compromete AWS, podria desencriptar el state.
- (-) El state file (que tiene secretos como outputs de Terraform) esta cifrado con la misma clave que cualquier otro objeto S3.

**Opcion B: SSE-KMS con el CMK del proyecto**

- (+) El state file se cifra con una clave administrada por el equipo (no por AWS).
- (+) Mejor audit trail via CloudTrail (cada uso de la CMK genera un evento).
- (-) Trade-off chicken-and-egg: el CMK lo crea Terraform (`modules/security/main.tf`), pero el bucket debe existir ANTES de que Terraform corra por primera vez.
- (-) Soluciones:
  1. Bootstrap del CMK via script (fuera de Terraform). Mas complejidad.
  2. Bootstrap del bucket via `terraform import` despues del primer apply. Mas riesgo operativo.
- (-) Costo: $1/key/mes + $0.03/10k requests.

### Conclusion

El trade-off de bootstrap (chicken-and-egg) NO justifica el beneficio de seguridad marginal (AES256 ya cumple FIPS 140-2 y los compliance requirements del proyecto academico).

**Si en el futuro** se necesita SSE-KMS (e.g. por compliance enterprise), el path es:
1. Crear el CMK via script bash (fuera de Terraform).
2. Configurar el CMK con `policy` que restrinja uso al role de apply.
3. Modificar `scripts/bootstrap-backend.sh` para usar SSE-KMS al crear el bucket.
4. Documentar el proceso en este archivo.

---

## C16: Interface endpoints de prod (10 desde dia 1 vs incremental)

**Decision (2026-07-12): Mantener los 10 interface endpoints habilitados en prod desde el primer apply.**

### Estado actual (live/prod/terraform.tfvars)

```hcl
enable_all_endpoints_by_default = true
enable_s3_gateway_endpoint      = true
```

El `modules/endpoints/variables.tf` ya tiene un set definido de 10 endpoints:

```hcl
# De modules/endpoints/variables.tf
"ssm", "ssmmessages", "ec2messages", "secretsmanager",
"kms", "logs", "ecr.api", "ecr.dkr", "bedrock-runtime", "sts"
```

### Trade-off considerado

**Opcion A: 10 endpoints desde dia 1 (estado actual, $72/mes en prod)**

- (+) Configuracion simple: `enable_all_endpoints_by_default = true`.
- (+) Si 03-backend o 08-deep-agent necesitan un endpoint, ya esta. Sin reconfiguracion.
- (+) Mantiene trafico AWS privado (sin NAT para servicios AWS).
- (-) $72/mes baseline, incluso si los servicios no se usan todos.
- (-) Si se decide no usar Bedrock en prod, se pagan $7.20/mes por `bedrock-runtime` sin uso.

**Opcion B: Endpoints incrementales (recomendado por IMPROVEMENTS.md)**

- (+) Pagar solo por lo que se usa.
- (-) Complejidad: requiere identificar que servicios se usan antes del primer apply.
- (-) Si se identifica un servicio nuevo post-apply, requiere reconfiguracion + nuevo apply.
- (-) $72/mes en el peor caso (igual a Opcion A) si se usan todos eventualmente.

### Conclusion

Para un proyecto en Fase 0/1 (Fase 1.5 sin apply todavia), **la complejidad de Opcion B no se justifica** cuando:
- El costo maximo es $72/mes (similar a un cafe al mes).
- El proyecto no tiene 03-backend ni 08-deep-agent deployados, asi que ninguno de esos endpoints esta en uso todavia.
- Cuando llegue el momento de deployar 03-backend (que usa Bedrock + Lambda + S3 + CloudWatch), probablemente use 8 de los 10 endpoints, asi que el costo sera ~$58/mes.

**Si en algun momento** se quiere reducir costos, se puede:

1. Cambiar `enable_all_endpoints_by_default = false` en `live/prod/terraform.tfvars`.
2. Setear `enabled_endpoints = ["ssm", "logs", "secretsmanager", "kms", "ecr.api", "ecr.dkr", "sts", "s3"]` (8 endpoints, sin `bedrock-runtime` ni `ssmmessages`/`ec2messages` que son para ECS).
3. Aplicar.

El `validation` block en `enabled_endpoints` (PR #14) ya asegura que solo se aceptan esos valores.

---

## Items de IMPROVEMENTS.md aun abiertos

- **A6** (SEC-08): Verificar SG egress tras primer apply. BLOQUEADO hasta primer apply real.
- **C4** (TF-06): Terratest para modulos de Fase 2. NO APLICA hasta que se creen modulos `database`, `events`, `secrets`.
- **C9** (CI-03): Validacion explicita de inputs en terraform reusables. Pendiente (requiere steps custom).

## Referencias

- `D:\UNI\Spark\IMPROVEMENTS.md` - Lista completa de hallazgos y TODOs.
- `D:\UNI\Spark\PLAN_MULTI_ENV.md` - Plan multi-ambiente (seccion Costo de Networking).
- `D:\UNI\Spark\02-infrastructure\docs\IAM_ROLES.md` - Diseno de roles IAM.
- `D:\UNI\Spark\02-infrastructure\README.md` - Seccion "AWS Budgets y alertas de costo".
