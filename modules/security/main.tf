###############################################################################
# Module: security
#
# Meta-module deprecado. Los 3 sub-modulos fueron extraidos en Sprint 1:
#   - modules/oidc-github (PR4a, #62): 4 IAM roles + OIDC provider
#   - modules/kms (PR4b, #63): KMS CMK + alias
#   - modules/security-groups (PR4c, #64): 3 SGs + 5 SG rules
#
# Los callers (live/dev/main.tf) ahora invocan los 3 sub-modulos directamente.
# Este archivo queda como placeholder para evitar breakage de imports externos.
# Sera eliminado en Sprint 2 (cleanup).
#
# NOTA: Si necesitas los resources, instanciar los 3 sub-modulos en su lugar.
###############################################################################
