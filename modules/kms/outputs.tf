###############################################################################
# Outputs de modules/kms
###############################################################################

output "kms_key_arn" {
  description = "ARN de la CMK de Spark Match para este entorno."
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "KeyId de la CMK (util para policies que esperan key id, no arn)."
  value       = aws_kms_key.main.key_id
}

output "kms_alias_arn" {
  description = "ARN del alias CMK."
  value       = aws_kms_alias.main.arn
}

output "kms_alias_name" {
  description = "Nombre del alias CMK (alias/spark-match-{env}-main)."
  value       = aws_kms_alias.main.name
}
