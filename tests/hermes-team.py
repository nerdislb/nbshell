#!/usr/bin/env python3
"""Supervised team contracts: isolation, review, integration, and approval."""

import importlib.util
import json
import os
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
JOB_FILE = ROOT / "resources/hermes-jobs/manager.py"
TEAM_FILE = ROOT / "resources/hermes-team/manager.py"
os.environ["NBSHELL_HERMES_JOB_MANAGER"] = str(JOB_FILE)
spec = importlib.util.spec_from_file_location("hermes_team", TEAM_FILE)
teams = importlib.util.module_from_spec(spec); spec.loader.exec_module(teams)
assert all(teams._reviewer(provider, attempt) != provider for provider in teams.PROVIDERS for attempt in range(1, 8))

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); repo = root / "source"; repo.mkdir()
    subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    (repo / "base.txt").write_text("base\n"); subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", "base"], cwd=repo, check=True, capture_output=True)
    teams.STATE_ROOT = root / "team-state"; teams.DATA_ROOT = root / "team-data"
    jobs = teams._jobs(); jobs.STATE_ROOT = root / "job-state"; jobs.DATA_ROOT = root / "job-data"; jobs.MANAGER = JOB_FILE
    teams._jobs = lambda: jobs
    plan = json.dumps({"tasks": [{"title": "Marker", "provider": "codex", "instructions": "Add marker"}], "checks": [["python3", "-c", "from pathlib import Path; assert Path('marker.txt').read_text() == 'ok\\n'"]]})
    class FakeProcess: pid = 4242
    with patch.object(teams, "_spawn", return_value=4242): team = teams.create(str(repo), "Safely add a marker", plan)
    task = teams._read(team["id"])["tasks"][0]
    with patch.object(jobs, "Popen", return_value=FakeProcess()):
        current = teams._read(team["id"]); teams._start_task(current, current["tasks"][0]); teams._write(current)
    job_id = teams._read(team["id"])["tasks"][0]["job_id"]
    def implement(job, provider, review=False):
        (jobs._workspace(job_id) / "marker.txt").write_text("ok\n")
        return subprocess.CompletedProcess([], 0, "done", "")
    with patch.object(jobs, "_run_agent", side_effect=implement): jobs.worker(job_id)
    with patch.object(jobs, "Popen", return_value=FakeProcess()): jobs.start_review(job_id, "claude")
    with patch.object(jobs, "_run_agent", return_value=subprocess.CompletedProcess([], 0, "VERDICT: APPROVE", "")): jobs.review_worker(job_id, "claude")
    current = teams._read(team["id"]); current["tasks"][0].update(status="approved"); teams._integrate(current)
    if os.environ.get("CI"):
        completed = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(teams.subprocess, "run", return_value=completed) as sandbox_run:
            teams._checks(current)
        sandbox_command = sandbox_run.call_args.args[0]
        assert sandbox_command[0] == "bwrap"
        assert "--unshare-all" in sandbox_command and "--die-with-parent" in sandbox_command
        assert "--bind" in sandbox_command and "/workspace" in sandbox_command
        assert sandbox_command[-len(current["checks"][0]):] == current["checks"][0]
    else:
        # The documented local release gate exercises the real namespace. GitHub's
        # container blocks user-namespace creation even when bubblewrap is installed.
        teams._checks(current)
    current.update(status="awaiting_approval", updated=teams._now()); teams._write(current)
    assert not (repo / "marker.txt").exists()
    try: teams.control(team["id"], "apply", False); raise AssertionError("approval gate failed")
    except SystemExit as exc: assert "requires --yes" in str(exc)
    applied = teams.control(team["id"], "apply", True)
    assert applied["status"] == "applied" and (repo / "marker.txt").read_text() == "ok\n"

print("Hermes supervised team contracts: OK")
