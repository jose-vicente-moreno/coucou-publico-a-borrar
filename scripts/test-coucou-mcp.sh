#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-mcp.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/ClaudeCode/CoucouMCP.swift \
    tests/CoucouMCPTests.swift -o "$TEST_DIR/coucou-mcp-tests"
"$TEST_DIR/coucou-mcp-tests" "$TEST_DIR/coucou-mcp.py"
/usr/bin/python3 tests/coucou_mcp_check.py "$TEST_DIR/coucou-mcp.py" "$TEST_DIR"
