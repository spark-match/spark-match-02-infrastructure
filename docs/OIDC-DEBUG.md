# OIDC debug: trust policy permissive

Cambio temporal de trust policy del role \spark-match-terraform-apply-prod\
para diagnosticar por qué falla OIDC. Acepta cualquier sub claim que
empiece con \epo:spark-match/spark-match-02-infrastructure:\.

Si con esta policy el apply-prod funciona, el problema es el patron de
sub claim. Si sigue fallando, el problema es el ARN del role en el
secret \AWS_APPLY_ROLE_ARN_PROD\.
