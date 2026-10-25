#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-claude-code.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
chmod +x tests/fake_claude.py
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/ClaudeCode/ClaudeCodeStream.swift \
    NotchBuddy/Sources/App/ClaudeCode/ClaudeCodeSession.swift \
    NotchBuddy/Sources/App/ClaudeCode/ClaudeCodeLocator.swift \
    tests/ClaudeCodeTests.swift -o "$TEST_DIR/claude-code-tests"
"$TEST_DIR/claude-code-tests" "$PWD/tests/fake_claude.py"
