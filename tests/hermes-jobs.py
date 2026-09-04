#!/usr/bin/env python3
"""Transactional Hermes job contracts, including the human approval gate."""

import importlib.util
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "resources/hermes-jobs/manager.py").read_text()
assert "provider_files[provider]" in source
assert "MAX_CONCURRENT_JOBS = 3" in source
assert "requires --yes" in source
assert '"--ask-for-approval"' not in source
spec = importlib.util.spec_from_file_location("hermes_jobs", ROOT / "resources/hermes-jobs/manager.py")
jobs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jobs)


gemini_command = jobs._provider_command("gemini", "audit", Path("/workspace"), False)
assert gemini_command[gemini_command.index("--print-timeout") + 1] == "25m"

with tempfile.TemporaryDirectory() as credential_temp:
    credential_root = Path(credential_temp)
    source_credential = credential_root / "source-token"
    local_credential = credential_root / "job-home" / "token"
    source_credential.write_text("expired-but-refreshable\n")
    source_credential.chmod(0o640)
    jobs._copy_private_file(source_credential, local_credential)
    assert local_credential.read_text() == "expired-but-refreshable\n"
    assert local_credential.stat().st_mode & 0o777 == 0o600
    local_credential.write_text("refreshed-in-sandbox\n")
    os.utime(local_credential, ns=(source_credential.stat().st_mtime_ns + 1, source_credential.stat().st_mtime_ns + 1))
    jobs._copy_private_file(source_credential, local_credential)
    assert local_credential.read_text() == "refreshed-in-sandbox\n"
    assert source_credential.read_text() == "expired-but-refreshable\n"


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    repo = root / "source"
    repo.mkdir()
    subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    (repo / "base.txt").write_text("base\n")
    subprocess.run(["git", "add", "base.txt"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-m", "base"], cwd=repo, check=True, capture_output=True)

    jobs.STATE_ROOT = root / "state"
    jobs.DATA_ROOT = root / "data"
    jobs.MANAGER = ROOT / "resources/hermes-jobs/manager.py"
    jobs.MAX_CONCURRENT_JOBS = 3

    sandbox, _ = jobs._bwrap("sandbox-test", repo, True, "codex")
    assert "--unshare-all" in sandbox and "--share-net" in sandbox
    if not os.environ.get("CI") and shutil.which("bwrap"):
        sentinel = subprocess.Popen(["sleep", "10"])
        try:
            isolated = subprocess.run(
                sandbox + ["/usr/bin/test", "!", "-e", f"/proc/{sentinel.pid}"],
                check=False,
            )
            assert isolated.returncode == 0
        finally:
            sentinel.terminate()
            sentinel.wait()
    leader = subprocess.Popen(
        ["python3", "-c", "import subprocess,time; child=subprocess.Popen(['sleep','30']); print(child.pid,flush=True); time.sleep(30)"],
        start_new_session=True, stdout=subprocess.PIPE, text=True,
    )
    assert leader.stdout is not None
    child_pid = int(leader.stdout.readline())
    try:
        assert jobs._terminate_process({"pid": leader.pid, "pid_start": jobs._process_start(leader.pid)})
        leader.wait(timeout=2)
        deadline = time.monotonic() + 2
        child_state = ""
        while time.monotonic() < deadline:
            try:
                child_state = Path(f"/proc/{child_pid}/stat").read_text().rpartition(") ")[2].split()[0]
            except (OSError, IndexError):
                child_state = "gone"
            if child_state in {"gone", "Z"}: break
            time.sleep(0.02)
        assert child_state in {"gone", "Z"}, "transaction child survived process-group cancellation"
    finally:
        if leader.poll() is None: os.killpg(leader.pid, 9)
    current_process = {"pid": os.getpid(), "pid_start": jobs._process_start(os.getpid())}
    assert jobs._process_alive(current_process) is True
    current_process["pid_start"] = "reused-process"
    assert jobs._process_alive(current_process) is False

    class FakeProcess:
        pid = os.getpid()

    with patch.object(jobs, "Popen", return_value=FakeProcess()):
        created = jobs.create("codex", str(repo), "Add a transaction marker")
    job_id = created["id"]

    def implement(job, provider, review=False):
        assert provider == "codex" and not review
        (jobs._workspace(job_id) / "result.txt").write_text("isolated\n")
        return subprocess.CompletedProcess([], 0, "implemented and tested", "")

    with patch.object(jobs, "_run_agent", side_effect=implement):
        jobs.worker(job_id)
    ready = jobs.list_jobs(job_id)
    assert ready["status"] == "ready" and ready["commit"]
    assert not (repo / "result.txt").exists()

    stale_id = "late-review"
    stale = {
        "schema": 1, "id": stale_id, "provider": "codex", "repository": str(repo),
        "branch": "main", "base": ready["base"], "task": "stale review", "status": "rejected",
        "created": jobs._now(), "updated": jobs._now(), "pid": 0, "pid_start": "", "commit": ready["commit"],
        "summary": "", "error": "", "reviews": [{"provider": "claude", "status": "running"}], "actions": [],
    }
    jobs._write(stale)
    with patch.object(jobs, "_run_agent", return_value=subprocess.CompletedProcess([], 0, "VERDICT: APPROVE", "")):
        jobs.review_worker(stale_id, "claude")
    assert jobs.list_jobs(stale_id)["status"] == "rejected"
    assert jobs.list_jobs(stale_id)["can_apply"] is False

    with patch.object(jobs, "Popen", return_value=FakeProcess()):
        jobs.start_review(job_id, "claude")
    with patch.object(jobs, "_run_agent", return_value=subprocess.CompletedProcess([], 0, "Looks good\nVERDICT: APPROVE", "")):
        jobs.review_worker(job_id, "claude")
    assert jobs.list_jobs(job_id)["can_apply"] is True

    try:
        jobs.apply_job(job_id, False)
        raise AssertionError("apply without human approval unexpectedly succeeded")
    except SystemExit as exc:
        assert "requires --yes" in str(exc)

    applied = jobs.apply_job(job_id, True)
    assert applied["status"] == "applied"
    assert (repo / "result.txt").read_text() == "isolated\n"

    dead_job = dict(stale, id="dead-worker", status="running", pid=2_147_483_647,
                    pid_start="1", reviews=[], error="")
    jobs._write(dead_job)
    dead = jobs.list_jobs(dead_job["id"])
    assert dead["status"] == "failed" and jobs.list_jobs()["running"] == 0, "dead jobs still consume admission capacity"
    dead_launcher = dict(dead_job, id="dead-launcher", status="queued", pid=0, pid_start="",
                         launcher_pid=2_147_483_647, launcher_start="1")
    jobs._write(dead_launcher)
    assert jobs.list_jobs(dead_launcher["id"])["status"] == "failed", "dead pre-spawn job was not reconciled"

    setattr(jobs, "MAX_CONCURRENT_JOBS", 1)
    gate = threading.Barrier(2)
    original_repo_info = jobs._repo_info
    original_list_jobs = jobs.list_jobs
    results = []

    def synchronized_repo_info(path):
        result = original_repo_info(path)
        gate.wait()
        return result

    def slow_list_jobs(*args, **kwargs):
        result = original_list_jobs(*args, **kwargs)
        time.sleep(0.05)
        return result

    def create_concurrently():
        try:
            results.append(jobs.create("codex", str(repo), "Concurrent admission test"))
        except SystemExit as exc:
            results.append(str(exc))

    with patch.object(jobs, "_repo_info", side_effect=synchronized_repo_info), \
            patch.object(jobs, "list_jobs", side_effect=slow_list_jobs), \
            patch.object(jobs, "Popen", return_value=FakeProcess()):
        threads = [threading.Thread(target=create_concurrently) for _ in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
    assert sum(isinstance(result, dict) for result in results) == 1
    assert sum("At most 1" in result for result in results if isinstance(result, str)) == 1

print("Hermes transaction contracts: OK")
