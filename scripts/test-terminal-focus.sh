#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-terminal-focus.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/TerminalFocus.swift \
    tests/TerminalFocusTests.swift -o "$TEST_DIR/terminal-focus-tests"
"$TEST_DIR/terminal-focus-tests"
