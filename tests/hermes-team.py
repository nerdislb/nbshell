#!/usr/bin/env python3
"""Supervised team contracts: isolation, review, integration, and approval."""

import importlib.util
import json
import os
import subprocess
import tempfile
import threading
import time
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
    class FakeProcess: pid = os.getpid()
    with patch.object(teams, "_spawn", return_value=4242): team = teams.create(str(repo), "Safely add a marker", plan)
    current_process = {"pid": os.getpid(), "pid_start": teams._process_start(os.getpid())}
    assert teams._process_alive(current_process) is True
    current_process["pid_start"] = "reused-process"
    assert teams._process_alive(current_process) is False
    stale = teams._read(team["id"])
    cancelled = dict(stale); cancelled["status"] = "cancelled"; teams._write(cancelled)
    assert teams._persist_active(stale) is False
    assert teams._read(team["id"])["status"] == "cancelled"
    teams._write(stale)
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

    race = dict(stale, id="cancel-race", status="running", pid=os.getpid(),
                pid_start=teams._process_start(os.getpid()), tasks=[dict(task, job_id="", status="queued", attempt=0, history=[])])
    teams._write(race)
    create_entered = threading.Event(); release_create = threading.Event(); terminated = []

    def delayed_create(*_args):
        create_entered.set(); release_create.wait(2)
        return {"id": "owned-job"}

    with patch.object(jobs, "create", side_effect=delayed_create), \
            patch.object(jobs, "_read", return_value={"id": "owned-job", "pid": 0}), \
            patch.object(jobs, "_terminate_process", side_effect=lambda job: terminated.append(job["id"])):
        starter = threading.Thread(target=lambda: teams._start_task(race, race["tasks"][0]))
        canceller = threading.Thread(target=lambda: teams.control(race["id"], "cancel", True))
        starter.start(); assert create_entered.wait(1)
        canceller.start(); time.sleep(0.05)
        assert canceller.is_alive(), "cancellation bypassed the task ownership lock"
        release_create.set(); starter.join(); canceller.join()
    assert teams._read(race["id"])["status"] == "cancelled" and terminated == [race["id"], "owned-job"]

    dead_launcher = dict(race, id="dead-launcher", status="planning", pid=0, pid_start="",
                         launcher_pid=2_147_483_647, launcher_start="1")
    teams._write(dead_launcher)
    assert teams.list_teams(dead_launcher["id"])["status"] == "paused"

    hidden = dict(race, id="hidden-active", status="running", created=1, pid=os.getpid(),
                  pid_start=teams._process_start(os.getpid()), launcher_pid=0, launcher_start="")
    teams._write(hidden)
    for index in range(11):
        finished = dict(race, id=f"recent-final-{index}", status="cancelled", created=100 + index, pid=0, pid_start="")
        teams._write(finished)
    assert not any(row["id"] == hidden["id"] for row in teams.list_teams()["teams"])
    assert teams.list_teams()["running"] == 1
    try: teams.create(str(repo), "Must not bypass hidden active team", plan); raise AssertionError("hidden active team was ignored")
    except SystemExit as exc: assert "Only one" in str(exc)
    hidden["status"] = "cancelled"; teams._write(hidden)

    gate = threading.Barrier(2)
    original_plan = teams._plan
    original_list_teams = teams.list_teams
    admissions = []

    def synchronized_plan(value):
        result = original_plan(value)
        gate.wait()
        return result

    def slow_list_teams(*args, **kwargs):
        result = original_list_teams(*args, **kwargs)
        time.sleep(0.05)
        return result

    def create_concurrently():
        try:
            admissions.append(teams.create(str(repo), "Concurrent team admission", plan))
        except SystemExit as exc:
            admissions.append(str(exc))

    with patch.object(teams, "_plan", side_effect=synchronized_plan), \
            patch.object(teams, "list_teams", side_effect=slow_list_teams), \
            patch.object(teams, "_spawn", return_value=os.getpid()):
        threads = [threading.Thread(target=create_concurrently) for _ in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
    assert sum(isinstance(result, dict) for result in admissions) == 1
    assert sum("Only one" in result for result in admissions if isinstance(result, str)) == 1

print("Hermes supervised team contracts: OK")
