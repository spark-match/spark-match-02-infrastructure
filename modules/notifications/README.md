# Module: notifications

Cubre los recursos "de cuenta" relacionados a notificaciones operacionales de Spark Match, independientes del environment:

- **SNS topic** (`spark-match-budget-alerts`) para alertas de AWS Budget
- **SNS topic policy** que permite publish a `budgets.amazonaws.com`
- **Suscripciones email** (configurables via `var.email_endpoints`)
- **AWS Budget** (`spark-match-monthly-total`, $200/mes, COST) con 2 notificaciones:
  - `ACTUAL > 80%`: alerta reactiva cuando el costo real llega al 80% de $200 (=$160)
  - `FORECASTED > 100%`: alerta predictiva cuando AWS pronostica que el mes cerrara > $200

## Por que este modulo es de cuenta (no de environment)

- AWS Budget es un recurso de cuenta, no se replica por env.
- SNS topic es compartido (mismo ARN para todos los envs).
- Las suscripciones de email son del equipo (independiente del env).

Si en el futuro hay alerting diferenciado por env, se puede partir en `modules/notifications` (cuenta) + `modules/dev/notifications`, etc.

## Limitaciones conocidas

- **Suscripciones email no se pueden auto-confirmar**: AWS siempre envia un email de confirmacion al destinatario cuando Terraform crea una nueva suscripcion. Hay que hacer clic en el link.
- **Free tier SNS**: 1,000 publishes/mes gratis los primeros 12 meses; despues, primeros 1M publishes/mes gratis. Para alertas de budget a 2 personas, costo es $0.

## Ejemplo de uso

```hcl
module "notifications" {
  source = "../../modules/notifications"

  email_endpoints = [
    "ahincho@unsa.edu.pe",
    "ftapara@unsa.edu.pe",
  ]

  # Opcionales (defaults razonables):
  # budget_limit_amount = 200
  # topic_name          = "spark-match-budget-alerts"
  # budget_name         = "spark-match-monthly-total"
}
```

## Importar recursos existentes

Este modulo es compatible con `terraform import`. Los recursos se importan en este orden:

```bash
# 1. SNS topic
terraform import module.notifications.aws_sns_topic.budget_alerts \
  arn:aws:sns:us-east-1:681526276858:spark-match-budget-alerts

# 2. SNS topic policy
terraform import module.notifications.aws_sns_topic_policy.budget_alerts \
  arn:aws:sns:us-east-1:681526276858:spark-match-budget-alerts

# 3. SNS topic subscription (una por email)
terraform import 'module.notifications.aws_sns_topic_subscription.email["ahincho@unsa.edu.pe"]' \
  arn:aws:sns:us-east-1:681526276858:spark-match-budget-alerts:a4cd2a4b-ac42-4fa4-b4ba-caf9bda5b7ba

# 4. AWS Budget
terraform import module.notifications.aws_budgets_budget.monthly \
  681526276858:spark-match-monthly-total
```

Las suscripciones pendientes (`PendingConfirmation`) NO se importan: Terraform las crea al hacer `terraform apply` y AWS envia un nuevo email de confirmacion.