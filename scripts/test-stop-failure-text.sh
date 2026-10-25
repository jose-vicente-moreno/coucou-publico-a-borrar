#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-stop-failure.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/DiffEngine.swift \
    NotchBuddy/Sources/App/StopFailureText.swift \
    tests/StopFailureTextTests.swift -o "$TEST_DIR/stop-failure-tests"
"$TEST_DIR/stop-failure-tests"
