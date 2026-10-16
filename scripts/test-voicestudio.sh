#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-voicestudio.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -warnings-as-errors \
    NotchBuddy/Sources/App/Voice/VoiceStudioAPI.swift \
    tests/VoiceStudioAPITests.swift -o "$TEST_DIR/voicestudio-tests"
"$TEST_DIR/voicestudio-tests"
