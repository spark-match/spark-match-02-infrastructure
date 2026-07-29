# ADR 0001 — OIDC thumbprint rotation for GitHub Actions

> **Status**: accepted
> **Date**: 2026-07-28
> **Deciders**: @ahincho
> **Sprint**: 1 (security hardening)

## Context

GitHub Actions OIDC tokens (`token.actions.githubusercontent.com`) se firman
con certificados rotados por GitHub. AWS exige que el `aws_iam_openid_connect_provider`
incluya los thumbprints SHA-1 de los certificados activos para validar la
firma del JWT.

GitHub introdujo un **nuevo certificado en 2026** (thumbprint `a6840fac...`)
para complementar el certificado estable desde 2023 (thumbprint `6938fd4d...`).
AWS requiere que ambos thumbprints esten en el `thumbprint_list` del OIDC
provider **durante la transicion**.

### Estado actual en el repo (Q4 28-jul-2026)

`modules/security/main.tf` no crea el `aws_iam_openid_connect_provider`
(esa parte la hace `modules/oidc-github` en orion, pero en spark-match no
se ha extraido aun — sigue inline en `modules/security`). El thumbprint
esta hardcoded.

**Riesgo**: si GitHub rota el certificado viejo y solo esta el thumbprint
nuevo en el provider, los tokens emitidos durante la ventana de rotacion
pueden ser invalidos. Si GitHub rota al nuevo y solo esta el viejo AWS
empieza a rechazar tokens, fallando todos los apply/plan.

## Decision

Adoptar el patron de **`var.oidc_provider_thumbprints` con 2 thumbprints
(default)** siguiendo el ejemplo de `orion-infrastructure/modules/oidc-github/variables.tf`:

```hcl
variable "oidc_provider_thumbprints" {
  description = "Thumbprints de los certificados del OIDC provider de GitHub Actions. GitHub rota certificados; mantener ambos durante la transicion."
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",  # estable desde 2023
    "a6840fac8d59c1b2737d22c4dd2d7485b69e9b8e",  # nuevo cert, 2026
  ]
}
```

**Reglas operacionales**:

1. **SIEMPRE mantener ambos thumbprints** mientras AWS / GitHub no confirmen
   que el cert viejo fue removido del lado de GitHub.
2. Cuando se elimine el viejo, hacer un PR con:
   - Update del default en `var.oidc_provider_thumbprints`.
   - Update de este ADR con la fecha de la rotacion.
   - Run de `aws sts assume-role-with-web-identity` despues del apply
     con un token de prueba (`gh api `action_base64'') para confirmar
     que el nuevo thumbprint es suficiente.
3. **Nunca** dejar `thumbprint_list = []` (causa `InvalidParameter: Thumbprint list must not be empty`).
4. **Nunca** usar 1 thumbprint (riesgo de rotacion).

## Consequences

### Positivas

- OIDC provider sigue funcionando durante la rotacion de certs de GitHub.
- Sigue el patron de `orion-infrastructure` (consistencia cross-repo).
- Parametrizable via variable — facil de actualizar sin tocar el modulo.

### Negativas

- Hay que validar empiricamente que el thumbprint `a6840fac...` es el correcto
  (no tenemos source-of-truth oficial de GitHub para "los thumbprints activos";
  lo que funciona en produccion hoy es el source-of-truth).
- Cualquier cambio requiere un `terraform apply` para refresh.

## Verification

Para verificar el thumbprint actual de `token.actions.githubusercontent.com`:

```bash
# AWS CLI: describe el OIDC provider ya creado
aws iam list-open-id-connect-providers --profile spark-match-admin

# OIDC discovery URL (thumbprint del cert activo)
curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq .

# OpenSSL: extraer thumbprint directo del cert
echo | openssl s_client -servername token.actions.githubusercontent.com -connect token.actions.githubusercontent.com:443 2>/dev/null | openssl x509 -fingerprint -noout
```

El resultado debe matchear uno de los 2 thumbprints del default.

## References

- `orion-infrastructure/modules/oidc-github/variables.tf` lineas 28-34 (default).
- `orion-infrastructure/modules/oidc-github/main.tf` linea 66 (uso).
- `orion-infrastructure/AGENTS.md` seccion "Reglas duras" item 5.
- AWS docs: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
- GitHub OIDC docs: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
