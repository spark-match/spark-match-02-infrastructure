#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Spark Match
# =============================================================================
# .pre-commit-hooks/commit-msg.sh - validate Conventional Commits format
# =============================================================================
# Lightweight mirror of the CI-side commitlint check defined in
# .commitlintrc.json. Runs from the pre-commit framework via the local
# `commit-msg-conventional` hook declared in .pre-commit-config.yaml.
#
# Scope enum matches .commitlintrc.json scope-enum (25 infra scopes):
#   oidc networking security endpoints kms notifications iam observability
#   rds lambda budget storage secrets events dynamodb ssm live modules
#   terraform ci deps docs governance scripts repo
#
# Type enum matches @commitlint/config-conventional defaults (10 types):
#   feat fix chore docs refactor test build ci perf revert
#
# Subject rules:
#   - lowercase (no uppercase letters)
#   - no trailing period
#   - header (full first line) <= 100 chars
#
# Exempted prefixes (pass through unchanged):
#   - Merge ...
#   - Revert "..."
#   - fixup! ...
#   - squash! ...
#   - amend! ...
#
# Reference: AGENTS.md (spark-match-02-infrastructure), the canonical
# source of truth for scope naming. Mirrors .commitlintrc.json.
# =============================================================================

set -euo pipefail

COMMIT_MSG_FILE="$1"
COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

FIRST_LINE=$(printf '%s\n' "$COMMIT_MSG" | head -n 1)
if [[ "$FIRST_LINE" =~ ^Merge\  ]] \
   || [[ "$FIRST_LINE" =~ ^Revert\ \" ]] \
   || [[ "$FIRST_LINE" =~ ^fixup!\  ]] \
   || [[ "$FIRST_LINE" =~ ^squash!\  ]] \
   || [[ "$FIRST_LINE" =~ ^amend!\  ]]; then
  exit 0
fi

err() {
  echo "::error::$*" >&2
  exit 1
}

TYPE_RE='^(feat|fix|chore|docs|refactor|test|build|ci|perf|revert)'
SCOPE_RE='(oidc|networking|security|endpoints|kms|notifications|iam|observability|rds|lambda|budget|storage|secrets|events|dynamodb|ssm|live|modules|terraform|ci|deps|docs|governance|scripts|repo)'

if [[ ! "$FIRST_LINE" =~ ${TYPE_RE}(\(${SCOPE_RE}\))?:\ .+ ]]; then
  err "header '$FIRST_LINE' does not match Conventional Commits shape '<type>(<scope>): <subject>' or '<type>: <subject>'"
fi

SUBJECT="${FIRST_LINE#*: }"

if (( ${#FIRST_LINE} > 100 )); then
  err "header is ${#FIRST_LINE} chars; max 100 (subject was ${#SUBJECT})"
fi

if [[ "$SUBJECT" =~ \.$ ]]; then
  err "subject must not end with '.'"
fi

if [[ "$SUBJECT" =~ [A-Z] ]]; then
  err "subject must be lowercase (found uppercase)"
fi
