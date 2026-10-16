#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-brain-config.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir "$TEST_DIR/vaults"
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/SafeWebURL.swift \
    NotchBuddy/Sources/App/Brain/BrainConfig.swift \
    tests/BrainConfigTests.swift -o "$TEST_DIR/brain-config-tests"
"$TEST_DIR/brain-config-tests" "$TEST_DIR/vaults" docs/brain.example.json
