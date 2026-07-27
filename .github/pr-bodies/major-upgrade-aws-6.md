@ahincho

## Summary
Major version upgrade of the AWS Terraform provider from `~> 5.40` to `~> 6.0` (resolved to 6.56.0), addressing the open dependabot PRs #56 and #57 with the necessary code fix for breaking changes.

## Changes
- **6 versions.tf** files updated: `~> 5.40` -> `~> 6.0` (live/dev, live/prod, modules/networking, modules/security, modules/endpoints, modules/notifications)
- **6 .terraform.lock.hcl** regenerated with hashicorp/aws 6.56.0
- **1 breaking change fix** in modules/networking/main.tf:262: `data.aws_region.current.name` -> `data.aws_region.current.region` (the only deprecated attribute our code references)

## Validation
- `terraform init -upgrade -backend=false` in all 6 dirs: OK
- `terraform validate` in all 6 dirs: OK
- 0 breaking changes affecting our specific resources (no S3, RDS, ECS, Lambda; mostly VPC + IAM + KMS + SNS + CloudWatch)

## Already 6.x-compatible (no change needed)
- `aws_eip`: already uses `domain = "vpc"` (the new attribute; `vpc` was removed)
- `aws_flow_log`: already uses `log_destination` (the new attribute; `log_group_name` was removed)

## Refs
- Dependabot PRs #56, #57 (superseded)
- AWS provider 6.0.0 CHANGELOG: https://github.com/hashicorp/terraform-provider-aws/blob/v6.0.0/CHANGELOG.md

cc @ahincho
