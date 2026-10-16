#!/usr/bin/env python3
"""Stand-in for `claude -p --input-format stream-json --output-format stream-json`.

Reads one JSON user message per line on stdin and answers each with the same
event shapes the real CLI emits (system/init, stream_event text deltas, result).
Special prompts drive the edge cases the Swift tests exercise:
  CRASH  -> exit 3 in the middle of the turn
  SLOW   -> never answer (the caller must time out)
  TOOL   -> announce a tool_use block before the answer
  DENY   -> finish the turn as an error with a permission denial
"""
import json
import os
import sys
import time

SESSION = "sess-fake-123"
args = sys.argv[1:]
resume = args[args.index("--resume") + 1] if "--resume" in args else "none"
if resume == "bad-session":
    sys.stderr.write("No conversation found with session ID: bad-session\n")
    sys.exit(1)


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def delta(text, parent=None):
    emit({"type": "stream_event", "parent_tool_use_id": parent, "session_id": SESSION,
          "event": {"type": "content_block_delta", "index": 0,
                    "delta": {"type": "text_delta", "text": text}}})


turn = 0
for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    message = json.loads(raw)
    blocks = message["message"]["content"]
    text = " ".join(b.get("text", "") for b in blocks if b.get("type") == "text")
    turn += 1
    emit({"type": "system", "subtype": "init", "session_id": SESSION, "model": "fake"})
    if text == "CRASH":
        sys.exit(3)
    if text == "SLOW":
        time.sleep(30)
        continue
    if text == "TOOL":
        emit({"type": "stream_event", "parent_tool_use_id": None, "session_id": SESSION,
              "event": {"type": "content_block_start", "index": 1,
                        "content_block": {"type": "tool_use", "name": "Read", "id": "t1", "input": {}}}})
        delta("sub-agent noise", parent="toolu_parent")
    if text == "RESULT_THEN_EXIT":
        emit({"type": "result", "subtype": "success", "is_error": False, "session_id": SESSION,
              "result": "last words", "permission_denials": []})
        os._exit(0)
    if text == "DENY":
        emit({"type": "result", "subtype": "success", "is_error": True, "session_id": SESSION,
              "result": "I could not write the file.",
              "permission_denials": [{"tool_name": "Write", "tool_use_id": "t2", "tool_input": {}}]})
        continue
    emit({"type": "stream_event", "parent_tool_use_id": None, "session_id": SESSION,
          "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}})
    delta("Hola")
    delta(" mundo")
    emit({"type": "assistant", "session_id": SESSION,
          "message": {"content": [{"type": "text", "text": "Hola mundo"}]}})
    emit({"type": "result", "subtype": "success", "is_error": False, "session_id": SESSION,
          "result": f"Hola mundo|turn={turn}|resume={resume}|pid={os.getpid()}|env={os.environ.get('COUCOU_TEST_ENV', '-')}",
          "permission_denials": []})
