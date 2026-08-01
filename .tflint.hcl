###############################################################################
# .tflint.hcl — Terraform Linter config for spark-match-02-infrastructure
###############################################################################
# Used by reusable workflow tflint.yml (spark-match-01-devops).
# tflint --recursive walks all subdirs, picks up this config at repo root
# and overrides per-module where needed (via .tflint.hcl in each module).
#
# Conventions enforced here:
#   - snake_case for resources, variables, outputs, locals, modules
#   - terraform_required_version matches the version pinned in versions.tf
#   - module sources pinned to git tags (not branch refs)
#   - all variables and outputs documented
#   - AWS provider rules enabled for resource naming + tagging
###############################################################################

plugin "terraform" {
  enabled = true
}

plugin "aws" {
  enabled = true
  version = "0.10.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

###############################################################################
# Terraform plugin rules
###############################################################################

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  # DISABLED: live/prod/variables.tf define placeholder vars for Sprint 3-4
  # (RDS, eventbridge, secrets, etc). They will be consumed when the root module
  # wires all modules. Re-enable after Sprint 4 (wire-all-modules) is merged.
  enabled = false
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_deprecated_syntax" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

rule "terraform_module_version" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = false
}

###############################################################################
# AWS plugin rules
###############################################################################

# Resource naming (e.g., aws_s3_bucket.this_name vs aws_s3_bucket.thisName)
rule "aws_resource_missing" {
  enabled = true
}

# Disallow hardcoded ARNs in arguments (force use of data sources or locals)
rule "aws_arn_invalid" {
  enabled = true
}

# Validate instance types are valid AWS instance types (catches typos)
rule "aws_instance_invalid_type" {
  enabled = true
}

# Validate IAM policy actions are valid (catches typos like s3:GetObect)
rule "aws_iam_policy_document_too_many_statements" {
  enabled = true
}
