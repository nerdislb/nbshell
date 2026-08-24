#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "shell/scripts/ai-local-stats.py"

with tempfile.TemporaryDirectory() as name:
    home = pathlib.Path(name)
    codex = home / ".codex/sessions/2026/08/24"
    claude = home / ".claude/projects/demo"
    codex.mkdir(parents=True)
    claude.mkdir(parents=True)
    stamp = "2026-08-24T12:00:00Z"
    (codex / "session.jsonl").write_text("\n".join((
        json.dumps({"timestamp": stamp, "type": "turn_context", "payload": {"model": "gpt-test"}}),
        json.dumps({"timestamp": stamp, "type": "event_msg", "payload": {"type": "token_count", "info": {"total_token_usage": {"total_tokens": 120}}}}),
    )) + "\n")
    (claude / "session.jsonl").write_text(json.dumps({
        "timestamp": stamp, "type": "assistant",
        "message": {"model": "claude-test", "usage": {"input_tokens": 40, "output_tokens": 10, "cache_read_input_tokens": 5}},
    }) + "\n")
    env = os.environ.copy()
    env["HOME"] = str(home)
    data = json.loads(subprocess.check_output(["python3", str(TOOL)], text=True, env=env))
    assert data["codex"]["totalTokens"] == 120
    assert data["codex"]["models"] == [{"name": "gpt-test", "tokens": 120}]
    assert data["claude"]["totalTokens"] == 55
    assert data["claude"]["models"] == [{"name": "claude-test", "tokens": 55}]

print("AI local stats: OK")
