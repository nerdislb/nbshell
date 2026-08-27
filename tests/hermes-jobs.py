#!/usr/bin/env python3
"""Transactional Hermes job contracts, including the human approval gate."""

import importlib.util
import subprocess
import tempfile
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

    class FakeProcess:
        pid = 12345

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

print("Hermes transaction contracts: OK")
