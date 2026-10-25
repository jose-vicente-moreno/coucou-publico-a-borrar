#!/usr/bin/env bash
# The nb-hook scripts live inside HookServer.swift as Swift string literals, so the
# Swift compiler only ever sees them as text. A bad merge, a stray delimiter or a
# broken edit leaves the app building perfectly and every hook dying at runtime with
# a SyntaxError nobody reads. This compiles them as Python so that failure is loud.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="NotchBuddy/Sources/App/HookServer.swift"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/coucou-hook-script.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

extract() {
    # Prints the lines between `private let <name> = """` and the next line that is
    # exactly `"""`.
    awk -v want="$1" '
        $0 == "private let " want " = \"\"\"" { inside = 1; next }
        inside && $0 == "\"\"\"" { exit }
        inside { print }
    ' "$SRC"
}

status=0
for name in nbHookPythonGitHub nbHookPythonAppStore; do
    out="$WORK/$name.py"
    extract "$name" > "$out"
    lines=$(wc -l < "$out" | tr -d ' ')
    if [ "$lines" -lt 50 ]; then
        echo "FAIL $name: extracted only $lines lines, the literal was not found"
        status=1
        continue
    fi
    if python3 -m py_compile "$out" 2>"$WORK/$name.err"; then
        echo "ok   $name ($lines lines) compiles as Python"
    else
        echo "FAIL $name does not compile as Python:"
        cat "$WORK/$name.err"
        status=1
    fi
    # The hook is what reports a stopped session, so losing the socket write or the
    # event name would be silent too. Assert the parts the app depends on.
    for needle in "add_session_name" "transcript_path" "AF_UNIX" "def main"; do
        if ! grep -q "$needle" "$out"; then
            echo "FAIL $name is missing \"$needle\""
            status=1
        fi
    done
done

if [ "$status" -eq 0 ]; then echo "All hook script tests passed."; fi
exit "$status"
