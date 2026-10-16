#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-brain-status.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir "$TEST_DIR/vaults"
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/SafeWebURL.swift \
    NotchBuddy/Sources/App/Brain/BrainConfig.swift \
    NotchBuddy/Sources/App/Brain/BrainVault.swift \
    NotchBuddy/Sources/App/Brain/BrainStatusScanner.swift \
    tests/BrainStatusScannerTests.swift -o "$TEST_DIR/brain-status-tests"
"$TEST_DIR/brain-status-tests" "$TEST_DIR/vaults"
