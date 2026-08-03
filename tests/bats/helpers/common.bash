#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Spark Match
# =============================================================================
# tests/bats/helpers/common.bash - shared setup for spark-match-02-infrastructure
# =============================================================================
# Provides REPO_ROOT (path to the repo root) so individual test files
# can resolve paths relative to the repo without hard-coding ../..
#
# Usage in a test file:
#
#   load 'helpers/common.bash'
#   @test "my-test" {
#     [ -f "$REPO_ROOT/.commitlintrc.json" ]
#   }
#
# bats loads helpers relative to the test file's directory, so this
# helper must live under tests/bats/helpers/ for `load 'helpers/common.bash'`
# to resolve.
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export REPO_ROOT
