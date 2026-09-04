#!/usr/bin/env python3
"""Second Brain proposals preserve vault boundaries and require approval."""

import importlib.util
import os
import subprocess
import tempfile
import threading
import time
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
    with patch.object(brain, "_spawn_review", return_value=os.getpid()):
        created = brain.create("01_Projects/project.md", "## Confirmed\n\nSafe fact.\n", "append", "codex", "claude", "Record confirmed test")
    proposal_id = created["id"]
    assert note.read_text() == "# Existing\n" and unrelated.read_text() == "user work\n"
    jobs = brain._jobs()
    with patch.object(jobs, "_run_agent", return_value=subprocess.CompletedProcess([], 0, "Reviewed\nVERDICT: APPROVE", "")), patch.object(brain, "_jobs", return_value=jobs):
        brain.review_worker(proposal_id)
    assert brain.list_proposals(proposal_id)["can_apply"] is True
    try: brain.control(proposal_id, "apply", False); raise AssertionError("approval gate failed")
    except SystemExit as exc: assert "requires --yes" in str(exc)
    subprocess.run(["git", "add", "01_Projects/unrelated.md"], cwd=vault, check=True)
    subprocess.run(["git", "commit", "-m", "concurrent unrelated change"], cwd=vault, check=True, capture_output=True)
    try: brain.control(proposal_id, "apply", True); raise AssertionError("moved Brain base was accepted")
    except SystemExit as exc: assert "moved since proposal creation" in str(exc)
    subprocess.run(["git", "reset", "--mixed", "HEAD^"], cwd=vault, check=True, capture_output=True)
    applied = brain.control(proposal_id, "apply", True)
    assert applied["status"] == "applied"
    assert note.read_text() == "# Existing\n\n## Confirmed\n\nSafe fact.\n"
    assert unrelated.read_text() == "user work\n"
    changed = subprocess.run(["git", "show", "--pretty=", "--name-only", "HEAD"], cwd=vault, text=True, capture_output=True, check=True).stdout.splitlines()
    assert changed == ["01_Projects/project.md"]
    for forbidden in ("00_Meta/AGENTS.md", "05_Sources/source.md", "../escape.md", "01_Projects/not.txt"):
        try: brain._target(forbidden); raise AssertionError(f"accepted forbidden target {forbidden}")
        except SystemExit: pass

    with patch.object(brain, "_spawn_review", return_value=os.getpid()):
        late = brain.create("04_Inbox/late.md", "# Late\n", "create", "codex", "claude", "test stale completion")
    jobs = brain._jobs()
    late_record = brain._read(late["id"])
    with patch.object(brain, "_jobs", return_value=jobs), patch.object(jobs, "_terminate_process", return_value=True) as terminate:
        brain.control(late["id"], "reject", True)
    terminate.assert_called_once()
    with patch.object(jobs, "_run_agent", return_value=subprocess.CompletedProcess([], 0, "VERDICT: APPROVE", "")):
        brain.review_worker(late["id"])
    assert brain.list_proposals(late["id"])["status"] == "rejected"

    dead_launcher = dict(late_record, id="dead-launcher", status="reviewing", pid=0, pid_start="",
                         launcher_pid=2_147_483_647, launcher_start="1", revision=0)
    brain._write(dead_launcher)
    assert brain.list_proposals(dead_launcher["id"])["status"] == "revision_requested"
    with patch.object(brain, "_spawn_review", side_effect=OSError("spawn failed")):
        try: brain.revise(dead_launcher["id"], "# Retry\n"); raise AssertionError("failed reviewer spawn was accepted")
        except OSError: pass
    failed_spawn = brain._read(dead_launcher["id"])
    assert failed_spawn["status"] == "revision_requested" and not failed_spawn["launcher_pid"]
    assert brain.list_proposals(late["id"])["can_apply"] is False

    setattr(brain, "MAX_CONCURRENT_REVIEWS", 1)
    gate = threading.Barrier(2)
    original_safe_markdown = brain._safe_markdown
    original_list_proposals = brain.list_proposals
    admissions = []

    def synchronized_markdown(value):
        result = original_safe_markdown(value)
        gate.wait()
        return result

    def slow_list_proposals(*args, **kwargs):
        result = original_list_proposals(*args, **kwargs)
        time.sleep(0.05)
        return result

    def create_concurrently(target):
        try:
            admissions.append(brain.create(target, "# Concurrent\n", "create", "codex", "claude", "admission test"))
        except SystemExit as exc:
            admissions.append(str(exc))

    with patch.object(brain, "_safe_markdown", side_effect=synchronized_markdown), \
            patch.object(brain, "list_proposals", side_effect=slow_list_proposals), \
            patch.object(brain, "_spawn_review", return_value=os.getpid()):
        threads = [threading.Thread(target=create_concurrently, args=(f"04_Inbox/concurrent-{index}.md",)) for index in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
    assert sum(isinstance(result, dict) for result in admissions) == 1
    assert sum("At most two" in result for result in admissions if isinstance(result, str)) == 1

print("Hermes Brain proposal contracts: OK")
