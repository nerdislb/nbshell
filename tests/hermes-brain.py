#!/usr/bin/env python3
"""Second Brain proposals preserve vault boundaries and require approval."""

import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
JOB_FILE = ROOT / "resources/hermes-jobs/manager.py"
FILE = ROOT / "resources/hermes-brain/manager.py"
os.environ["NBSHELL_HERMES_JOB_MANAGER"] = str(JOB_FILE)
spec = importlib.util.spec_from_file_location("hermes_brain", FILE)
brain = importlib.util.module_from_spec(spec); spec.loader.exec_module(brain)
assert brain.MAX_CONCURRENT_REVIEWS == 2

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); vault = root / "brain"; vault.mkdir()
    subprocess.run(["git", "init", "-b", "main"], cwd=vault, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=vault, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=vault, check=True)
    note = vault / "01_Projects/project.md"; note.parent.mkdir(); note.write_text("# Existing\n")
    unrelated = vault / "01_Projects/unrelated.md"; unrelated.write_text("base\n")
    subprocess.run(["git", "add", "."], cwd=vault, check=True); subprocess.run(["git", "commit", "-m", "base"], cwd=vault, check=True, capture_output=True)
    unrelated.write_text("user work\n")
    brain.BRAIN_ROOT = vault; brain.STATE_ROOT = root / "state"; brain.DATA_ROOT = root / "data"
    class FakeProcess: pid = 123
    with patch.object(brain, "_spawn_review", return_value=123):
        created = brain.create("01_Projects/project.md", "## Confirmed\n\nSafe fact.\n", "append", "codex", "claude", "Record confirmed test")
    proposal_id = created["id"]
    assert note.read_text() == "# Existing\n" and unrelated.read_text() == "user work\n"
    jobs = brain._jobs()
    with patch.object(jobs, "_run_agent", return_value=subprocess.CompletedProcess([], 0, "Reviewed\nVERDICT: APPROVE", "")), patch.object(brain, "_jobs", return_value=jobs):
        brain.review_worker(proposal_id)
    assert brain.list_proposals(proposal_id)["can_apply"] is True
    try: brain.control(proposal_id, "apply", False); raise AssertionError("approval gate failed")
    except SystemExit as exc: assert "requires --yes" in str(exc)
    applied = brain.control(proposal_id, "apply", True)
    assert applied["status"] == "applied"
    assert note.read_text() == "# Existing\n\n## Confirmed\n\nSafe fact.\n"
    assert unrelated.read_text() == "user work\n"
    changed = subprocess.run(["git", "show", "--pretty=", "--name-only", "HEAD"], cwd=vault, text=True, capture_output=True, check=True).stdout.splitlines()
    assert changed == ["01_Projects/project.md"]
    for forbidden in ("00_Meta/AGENTS.md", "05_Sources/source.md", "../escape.md", "01_Projects/not.txt"):
        try: brain._target(forbidden); raise AssertionError(f"accepted forbidden target {forbidden}")
        except SystemExit: pass

print("Hermes Brain proposal contracts: OK")
