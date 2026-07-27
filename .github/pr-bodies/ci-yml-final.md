## Why this PR

Hardening cycle INFRASTRUCTURE-UPGRADE.md Sprint 3 (final). After Sprint 1.1 (`terraform fmt` auto-fix, PR #50), Sprint 1.2+1.3 (`.yamllint.yml` + `.pre-commit-config.yaml` newline, PR #51), and Sprint 2.3 (5 inline `checkov:skip` directives, PR #52) all landed on dev, the only remaining quality lint still missing in CI is this `ci.yml`. Now that pre-conditions are met (no spurious findings), we can adopt the full pattern from `orion-infrastructure` without cascading failures.

## What

Adds `.github/workflows/ci.yml` with **8 jobs** (alphabetical), each delegating to a reusable in `spark-match-01-devops` pinned at `@main`:

| Job | Recipe | Purpose |
|---|---|---|
| actionlint | `actionlint.yml@main` | GH Actions syntax |
| checkov | `checkov.yml@main` | Terraform SCA |
| gitleaks | `gitleaks.yml@main` | Secret history |
| sonar | `sonar-terraform.yml@main` | SonarCloud Terraform |
| terraform-fmt | `terraform-fmt.yml@main` | `fmt -check -recursive` |
| terraform-validate | `terraform-validate.yml@main` | `init -backend=false` + `validate` |
| tflint | `tflint.yml@main` | `tflint --recursive` |
| yamllint | `yamllint.yml@main` | YAML lint (workflows excluded via `.yamllint.yml`) |

Triggers: `pull_request` to `main`/`dev`, `push` to `main`/`dev`, `workflow_dispatch`.

## Caveats (informational, not blocking this PR)

- **gitleaks** will fail until the `GITLEAKS_LICENSE` org secret is provisioned. Tracked as Sprint 3 follow-up. The recipe will not be silently skipped — it'll hard-fail and surface the missing-license error, which is the correct behavior.
- **terraform-plan.yml** + **terraform-apply.yml** remain the canonical "deployable plan" gate. This `ci.yml` only adds PR-time lint feedback.
- The existing `required_status_checks` in the ruleset (`Plan (dev)` + `Checkov`) are not affected by this change.

## Validation

Local: `git diff --stat` shows `+118 -0` on a single new file. No existing files touched.

## Out of scope

- ❌ Modifying `terraform-plan.yml` / `terraform-apply.yml` / `terraform-security-scan.yml` (infra lifecycle, not QA).
- ❌ Provisioning `GITLEAKS_LICENSE` org secret (requires org-admin action with gitleaks.io license).
- ❌ Syncing dev → main (separate chore PR after this lands).

Refs: `INFRASTRUCTURE-UPGRADE.md`, `BACKEND-HARDENIN-26-07.md`.
