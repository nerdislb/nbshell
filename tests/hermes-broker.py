#!/usr/bin/env python3
"""Static safety contracts for the optional Hermes advisory broker."""

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "resources/hermes-broker/server.py").read_text()
tree = ast.parse(source)

assert "ask_codex" in source and "ask_claude" in source and "ask_gemini" in source
assert "start_codex_job" in source and "start_claude_job" in source and "start_gemini_job" in source
assert "review_agent_job" in source and "agent_job_status" in source
assert "start_supervised_team" in source and "supervised_team_status" in source
assert "prepare_brain_proposal" in source and "revise_brain_proposal" in source and "brain_proposal_status" in source
assert "transaction repositories must be under" in source
assert "shell=True" not in source
assert "--dangerously" not in source and "--yolo" not in source
assert "--ignore-user-config" in source and "--ignore-rules" in source
assert "--die-with-parent" in source and "--ro-bind" in source
assert "RATE_LIMIT = 6" in source and "TIMEOUT_SECONDS = 120" in source
assert "request_chars" in source and '"question"' not in source[source.index("def _audit"):source.index("def _run_provider")]
assert any(isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "run" for node in ast.walk(tree))
assert '"apply"' not in source[source.index("JOB_TOOLS"):source.index("async def _advice")]

print("Hermes broker safety contracts: OK")
