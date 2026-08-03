#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Spark Match
# =============================================================================
# commitlint-config.bats - regression guards for .commitlintrc.json
# =============================================================================
# Locks down the structure of the canonical commitlint config so that:
#   - .commitlintrc.json is valid JSON and loadable by commitlint
#   - the @commitlint/config-conventional base is extended (so default
#     rules like header-max-length are inherited)
#   - the type-enum is exactly the 10 Conventional Commits types we allow
#   - the scope-enum matches the 20 infra scopes documented in AGENTS.md
#   - .pre-commit-hooks/commit-msg.sh reflects the same allowlists
#     (drift detector: if you add a scope to one, you must add it to
#     the other)
#
# The local hook .pre-commit-hooks/commit-msg.sh is pure-bash + grep
# (no Node, no commitlint binary install required). It duplicates a
# subset of the CI commitlint check. These tests guard against drift
# between the two.
# =============================================================================

load 'helpers/common.bash'

CONFIG="$REPO_ROOT/.commitlintrc.json"
HOOK="$REPO_ROOT/.pre-commit-hooks/commit-msg.sh"

# ---------------------------------------------------------------------------
# .commitlintrc.json structure
# ---------------------------------------------------------------------------

@test "commitlint-config: file exists at repo root" {
  [ -f "$CONFIG" ]
}

@test "commitlint-config: valid JSON" {
  run jq empty "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "commitlint-config: extends @commitlint/config-conventional" {
  run jq -r '.extends[0]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "@commitlint/config-conventional" ]
}

@test "commitlint-config: type-enum contains the 10 conventional types" {
  run jq -r '.rules["type-enum"][2] | length' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
  for t in feat fix chore docs refactor test build ci perf revert; do
    run jq -e --arg t "$t" '.rules["type-enum"][2] | index($t) != null' "$CONFIG"
    [ "$status" -eq 0 ]
  done
}

@test "commitlint-config: scope-enum contains the 20 infra-approved scopes" {
  run jq -r '.rules["scope-enum"][2] | length' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "20" ]
  for s in oidc networking security endpoints kms notifications iam observability rds lambda budget live modules terraform ci deps docs governance scripts repo; do
    run jq -e --arg s "$s" '.rules["scope-enum"][2] | index($s) != null' "$CONFIG"
    [ "$status" -eq 0 ]
  done
}

@test "commitlint-config: scope-empty is disabled (level 0) so scope is optional" {
  run jq -r '.rules["scope-empty"][0]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "commitlint-config: scope-enum is enabled (level 2, always)" {
  run jq -r '.rules["scope-enum"][0]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
  run jq -r '.rules["scope-enum"][1]' "$CONFIG"
  [ "$output" = "always" ]
}

@test "commitlint-config: scope-case is lower-case" {
  run jq -r '.rules["scope-case"][2]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "lower-case" ]
}

@test "commitlint-config: subject-case is lower-case" {
  run jq -r '.rules["subject-case"][2]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "lower-case" ]
}

@test "commitlint-config: subject-full-stop is never '.'" {
  run jq -r '.rules["subject-full-stop"][1]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "never" ]
  run jq -r '.rules["subject-full-stop"][2]' "$CONFIG"
  [ "$output" = "." ]
}

@test "commitlint-config: header-max-length is 100" {
  run jq -r '.rules["header-max-length"][2]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "100" ]
}

@test "commitlint-config: body-max-line-length is disabled (level 0)" {
  run jq -r '.rules["body-max-line-length"][0]' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "commitlint-config: has helpUrl pointing at AGENTS.md" {
  run jq -r '.helpUrl' "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGENTS.md"* ]]
  [[ "$output" == *"spark-match-02-infrastructure"* ]]
}

# ---------------------------------------------------------------------------
# .pre-commit-hooks/commit-msg.sh shape
# ---------------------------------------------------------------------------

@test "commitlint-config: hook script exists" {
  [ -f "$HOOK" ]
}

@test "commitlint-config: hook script is executable" {
  [ -x "$HOOK" ]
}

@test "commitlint-config: hook script header lists the 10 conventional types" {
  for t in feat fix chore docs refactor test build ci perf revert; do
    run grep -E "\\b$t\\b" "$HOOK"
    [ "$status" -eq 0 ]
  done
}

@test "commitlint-config: hook script lists the 20 infra scopes" {
  for s in oidc networking security endpoints kms notifications iam observability rds lambda budget live modules terraform ci deps docs governance scripts repo; do
    run grep -E "\\b$s\\b" "$HOOK"
    [ "$status" -eq 0 ]
  done
}

@test "commitlint-config: hook script checks header length (not just subject)" {
  # drift fix: the CI check applies header-max-length to the full FIRST_LINE.
  # The local hook must mirror that, not just check the subject.
  run grep -E 'FIRST_LINE' "$HOOK"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# .pre-commit-hooks/commit-msg.sh functional behavior
# ---------------------------------------------------------------------------

@test "commitlint-config: hook accepts a valid feat commit with infra scope" {
  run bash -c '
    echo -e "feat(terraform): add live/dev outputs" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -eq 0 ]
}

@test "commitlint-config: hook accepts a chore commit without scope" {
  run bash -c '
    echo -e "chore: sync dev into main" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -eq 0 ]
}

@test "commitlint-config: hook rejects a non-allowlisted scope" {
  run bash -c '
    echo -e "feat(bogus-scope): add thing" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}

@test "commitlint-config: hook rejects a non-allowlisted type" {
  run bash -c '
    echo -e "wip: random work" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}

@test "commitlint-config: hook rejects subject ending with period" {
  run bash -c '
    echo -e "fix(security): patch sg-default-egress." | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"trailing"* ]] || [[ "$output" == *"must not end"* ]]
}

@test "commitlint-config: hook rejects uppercase subject" {
  run bash -c '
    echo -e "feat(terraform): Add Live Outputs" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"lowercase"* ]]
}

@test "commitlint-config: hook rejects header > 100 chars" {
  LONG=$(printf 'x%.0s' {1..110})
  run bash -c '
    echo -e "fix(security): '"$LONG"'" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"max 100"* ]]
}

@test "commitlint-config: hook rejects long header even when subject is < 100 (drift fix)" {
  # Drift case: subject is 95 chars but prefix 'feat(terraform): ' (19 chars)
  # makes the full header 114 chars. The CI-side commitlint check rejects
  # this; the local hook must too. Pre-fix, the hook only checked subject
  # length and would have passed.
  LONG=$(printf 'x%.0s' {1..95})
  run bash -c '
    echo -e "feat(terraform): '"$LONG"'" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"header is"* ]]
}

@test "commitlint-config: hook allows Merge commits to pass through" {
  run bash -c '
    echo -e "Merge branch '\''feat/x'\'' into dev" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -eq 0 ]
}

@test "commitlint-config: hook allows Revert commits to pass through" {
  run bash -c '
    echo -e "Revert \"feat(terraform): add thing\"" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -eq 0 ]
}

@test "commitlint-config: hook allows fixup commits to pass through" {
  run bash -c '
    echo -e "fixup! feat(terraform): add thing" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -eq 0 ]
}

@test "commitlint-config: hook rejects header with wrong shape" {
  run bash -c '
    echo -e "no type here" | "'"$HOOK"'" /dev/stdin
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}
