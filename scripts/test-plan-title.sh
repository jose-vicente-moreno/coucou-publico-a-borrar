#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-plan-title.XXXXXX")"
trap ' rm -rf "$TEST_DIR" ' EXIT
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/PlanTitle.swift \
    tests/PlanTitleTests.swift -o "$TEST_DIR/plan-title-tests"
"$TEST_DIR/plan-title-tests"
