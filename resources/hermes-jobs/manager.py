#!/usr/bin/env python3
"""Transactional multi-provider jobs for nbshell's Hermes pilot.

Agents work in disposable local clones. Only this human-facing manager can
cherry-pick, install, or push a reviewed result into the source repository.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from subprocess import Popen


STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell/hermes-jobs"
DATA_ROOT = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nbshell/hermes-jobs"
MANAGER = Path(__file__).resolve()
PROVIDERS = {"codex", "claude", "gemini"}
FINAL_STATES = {"ready", "reviewed", "applied", "installed", "pushed", "rejected", "failed", "no_changes"}
MAX_TASK_CHARS = 12_000
MAX_JOBS = 30
MAX_CONCURRENT_JOBS = 3
GEMINI_PRINT_TIMEOUT = "25m"
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\b(?:sk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{16,}\b"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~-]{20,}\b", re.IGNORECASE),
    re.compile(r"\b(?:password|passwd|api[_ -]?key|access[_ -]?token|refresh[_ -]?token)\s*[:=]\s*\S+", re.IGNORECASE),
)


def _now() -> int:
    return int(time.time())


def _job_dir(job_id: str) -> Path:
    if not re.fullmatch(r"[a-z0-9-]{8,40}", job_id):
        raise SystemExit("Invalid job id")
    return STATE_ROOT / job_id


def _workspace(job_id: str) -> Path:
    return DATA_ROOT / job_id / "workspace"


def _read(job_id: str) -> dict:
    path = _job_dir(job_id) / "job.json"
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Unknown or damaged job: {job_id}") from exc


def _write(job: dict) -> None:
    directory = _job_dir(job["id"])
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / "job.json"
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(job, indent=2, sort_keys=True) + "\n")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


@contextmanager
def _locked(job_id: str):
    directory = _job_dir(job_id)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / ".lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def _run(command: list[str], *, cwd: Path | None = None, timeout: int = 30,
         capture: bool = True, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=capture,
                          timeout=timeout, check=check)


def _git(repo: Path, *args: str, timeout: int = 30, check: bool = True) -> subprocess.CompletedProcess:
    return _run(["git", "-C", str(repo), *args], timeout=timeout, check=check)


def _safe_task(value: str) -> str:
    task = str(value or "").strip()
    if not task:
        raise SystemExit("Task must not be empty")
    if len(task) > MAX_TASK_CHARS:
        raise SystemExit(f"Task exceeds {MAX_TASK_CHARS} characters")
    if "\x00" in task or any(pattern.search(task) for pattern in SECRET_PATTERNS):
        raise SystemExit("Task appears to contain a credential or private key")
    return task


def _repo_info(path: str) -> tuple[Path, str, str]:
    repo = Path(path).expanduser().resolve()
    top = Path(_git(repo, "rev-parse", "--show-toplevel").stdout.strip()).resolve()
    head = _git(top, "rev-parse", "HEAD").stdout.strip()
    branch = _git(top, "branch", "--show-current").stdout.strip()
    if not branch:
        raise SystemExit("The source repository must be on a named branch")
    return top, head, branch


def _trim_jobs() -> None:
    if not STATE_ROOT.is_dir():
        return
    rows = sorted((p for p in STATE_ROOT.iterdir() if p.is_dir()), key=lambda p: p.stat().st_mtime, reverse=True)
    for path in rows[MAX_JOBS:]:
        try:
            job = json.loads((path / "job.json").read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if job.get("status") in FINAL_STATES:
            shutil.rmtree(path, ignore_errors=True)
            shutil.rmtree(DATA_ROOT / path.name, ignore_errors=True)


def create(provider: str, repository: str, task: str) -> dict:
    if provider not in PROVIDERS:
        raise SystemExit("Unknown provider")
    task = _safe_task(task)
    repo, base, branch = _repo_info(repository)
    running = list_jobs().get("running", 0)
    if running >= MAX_CONCURRENT_JOBS:
        raise SystemExit(f"At most {MAX_CONCURRENT_JOBS} transaction jobs may run concurrently")
    job_id = time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3)
    job = {
        "schema": 1, "id": job_id, "provider": provider, "repository": str(repo),
        "branch": branch, "base": base, "task": task, "status": "queued",
        "created": _now(), "updated": _now(), "pid": 0, "commit": "",
        "summary": "", "error": "", "reviews": [], "actions": [],
    }
    _write(job)
    _trim_jobs()
    log = (_job_dir(job_id) / "worker.log").open("a")
    process = Popen(
        [sys.executable, str(MANAGER), "worker", job_id],
        stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True, close_fds=True,
    )
    log.close()
    job["pid"] = process.pid
    job["updated"] = _now()
    _write(job)
    return public_job(job)


def _sandbox_home(job_id: str, provider: str) -> Path:
    home = DATA_ROOT / job_id / "home" / provider
    for relative in (".codex", ".claude", ".gemini/antigravity-cli", ".cache", ".config", "runtime"):
        (home / relative).mkdir(parents=True, exist_ok=True, mode=0o700)
    return home


def _bind_file(command: list[str], source: Path, target: Path) -> None:
    if source.is_file():
        command.extend(["--ro-bind", str(source), str(target)])


def _copy_private_file(source: Path, target: Path) -> None:
    """Seed a writable, job-local credential copy without mutating the source."""
    if not source.is_file():
        return
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if target.is_file() and target.stat().st_mtime_ns >= source.stat().st_mtime_ns:
        return
    temporary = target.with_name(target.name + ".tmp")
    shutil.copyfile(source, temporary)
    temporary.chmod(0o600)
    temporary.replace(target)


def _bwrap(job_id: str, workspace: Path, writable: bool, provider: str) -> tuple[list[str], Path]:
    home = _sandbox_home(job_id, provider)
    command = [
        "bwrap", "--die-with-parent", "--new-session",
        "--ro-bind", "/usr", "/usr", "--ro-bind", "/opt", "/opt",
        "--symlink", "usr/bin", "/bin", "--symlink", "usr/lib", "/lib",
        "--symlink", "usr/lib", "/lib64", "--ro-bind", "/etc", "/etc",
        "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
        "--dir", "/run", "--dir", "/run/systemd",
        "--dir", "/workspace", "--dir", "/sandbox-home",
        "--dir", "/sandbox-home/.codex", "--dir", "/sandbox-home/.claude",
        "--dir", "/sandbox-home/.gemini", "--dir", "/sandbox-home/.gemini/antigravity-cli",
        "--dir", "/sandbox-home/.cache", "--dir", "/sandbox-home/.config",
    ]
    resolver = Path("/run/systemd/resolve")
    if resolver.exists():
        command.extend(["--ro-bind", str(resolver), str(resolver)])
    command.extend(["--bind" if writable else "--ro-bind", str(workspace), "/workspace"])
    command.extend(["--bind", str(home), "/sandbox-home"])
    real_home = Path.home()
    provider_files = {
        "codex": ((real_home / ".codex/auth.json", ".codex/auth.json"),),
        "claude": ((real_home / ".claude/.credentials.json", ".claude/.credentials.json"),),
        "gemini": tuple(
            (real_home / ".gemini/antigravity-cli" / name, ".gemini/antigravity-cli/" + name)
            for name in ("antigravity-oauth-token", "settings.json", "installation_id", "jetski_state.pbtxt")
        ),
    }
    for source, relative in provider_files[provider]:
        if provider == "gemini":
            _copy_private_file(source, home / relative)
        else:
            _bind_file(command, source, Path("/sandbox-home") / relative)
    env = {"HOME": "/sandbox-home", "XDG_CONFIG_HOME": "/sandbox-home/.config", "XDG_CACHE_HOME": "/sandbox-home/.cache", "XDG_RUNTIME_DIR": "/sandbox-home/runtime", "NO_COLOR": "1", "TERM": "dumb"}
    for key, value in env.items():
        command.extend(["--setenv", key, value])
    command.extend(["--chdir", "/workspace"])
    return command, home


def _agent_prompt(job: dict, review: bool = False) -> str:
    boundary = (
        "You are working inside a disposable transaction workspace. Never push, never access another "
        "directory, never request credentials, and never alter system configuration. The only project "
        "directory is /workspace; create and edit every deliverable there, never in a scratch directory. "
    )
    if review:
        return boundary + "Review the existing change read-only. Identify correctness, security, regressions, and missing tests. End with VERDICT: APPROVE or VERDICT: REVISE.\n\nTASK:\n" + job["task"]
    return boundary + (
        "Implement the task completely in this workspace. Run proportionate tests. Do not merely describe "
        "the solution. Leave all intended changes in the working tree and finish with a concise summary.\n\nTASK:\n"
    ) + job["task"]


def _provider_command(provider: str, prompt: str, workspace: Path, review: bool) -> list[str]:
    if provider == "codex":
        command = ["/usr/bin/codex", "exec", "-C", str(workspace), "--ephemeral", "--ignore-user-config", "--ignore-rules"]
        command += ["--sandbox", "read-only"] if review else ["--dangerously-bypass-approvals-and-sandbox"]
        return command + [prompt]
    if provider == "claude":
        return [
            "/usr/bin/claude", "--print", "--model", "sonnet", "--no-session-persistence",
            "--permission-mode", "plan" if review else "bypassPermissions", prompt,
        ]
    agy = str(Path.home() / ".local/share/antigravity/bin/agy")
    # bubblewrap makes the transaction workspace read-only for reviewers, so
    # headless tool approval can be skipped without widening filesystem access.
    permissions = ["--dangerously-skip-permissions"]
    return [agy, "--sandbox", "--new-project", "--add-dir", "/workspace",
            "--mode", "plan" if review else "accept-edits", *permissions,
            "--print-timeout", GEMINI_PRINT_TIMEOUT,
            "--print", prompt, "--output-format", "text"]


def _run_agent(job: dict, provider: str, review: bool = False,
               workspace_override: Path | None = None) -> subprocess.CompletedProcess:
    workspace = workspace_override or _workspace(job["id"])
    prefix, _ = _bwrap(job["id"], workspace, not review, provider)
    command = _provider_command(provider, _agent_prompt(job, review), Path("/workspace"), review)
    if provider == "gemini":
        vendor = Path.home() / ".local/share/antigravity"
        prefix.extend([
            "--dir", "/sandbox-home/.local", "--dir", "/sandbox-home/.local/share",
            "--ro-bind", str(vendor), "/sandbox-home/.local/share/antigravity",
            "--setenv", "PATH", "/usr/bin",
        ])
        command[0] = "/sandbox-home/.local/share/antigravity/bin/agy"
    return subprocess.run(prefix + command, text=True, capture_output=True, timeout=1800, check=False)


def worker(job_id: str) -> None:
    with _locked(job_id):
        job = _read(job_id)
        job.update(status="preparing", updated=_now(), error="")
        _write(job)
    workspace = _workspace(job_id)
    workspace.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        _run(["git", "clone", "--no-hardlinks", "--no-checkout", job["repository"], str(workspace)], timeout=180)
        _git(workspace, "checkout", "--detach", job["base"], timeout=60)
        _git(workspace, "config", "user.name", "nbshell Hermes Transaction")
        _git(workspace, "config", "user.email", "noreply@nbshell.local")
        with _locked(job_id):
            job = _read(job_id); job.update(status="running", updated=_now()); _write(job)
        result = _run_agent(job, job["provider"])
        (_job_dir(job_id) / "agent-output.txt").write_text((result.stdout or "")[-60000:])
        (_job_dir(job_id) / "agent-error.txt").write_text((result.stderr or "")[-12000:])
        if result.returncode:
            raise RuntimeError(f"{job['provider']} exited with code {result.returncode}")
        _git(workspace, "reset", "--soft", job["base"])
        _git(workspace, "add", "-A")
        changed = _git(workspace, "diff", "--cached", "--quiet", check=False).returncode != 0
        with _locked(job_id):
            job = _read(job_id)
            if not changed:
                job.update(status="no_changes", summary="Agent completed without repository changes", updated=_now())
            else:
                _git(workspace, "commit", "-m", f"Hermes transaction {job_id}: {job['task'][:60]}", timeout=60)
                commit = _git(workspace, "rev-parse", "HEAD").stdout.strip()
                stat = _git(workspace, "diff", "--stat", f"{job['base']}..{commit}").stdout.strip()
                job.update(status="ready", commit=commit, summary=stat, updated=_now())
            job["pid"] = 0; _write(job)
    except Exception as exc:
        with _locked(job_id):
            job = _read(job_id); job.update(status="failed", error=str(exc)[:500], pid=0, updated=_now()); _write(job)


def start_review(job_id: str, provider: str) -> dict:
    if provider not in PROVIDERS:
        raise SystemExit("Unknown provider")
    with _locked(job_id):
        job = _read(job_id)
        if job["status"] not in {"ready", "reviewed"}:
            raise SystemExit("Job is not ready for review")
        if provider == job["provider"]:
            raise SystemExit("Reviewer must differ from the implementing provider")
        if any(row.get("provider") == provider and row.get("status") in {"running", "approved"} for row in job["reviews"]):
            raise SystemExit("This provider already reviewed the job")
        job["reviews"].append({"provider": provider, "status": "running", "started": _now(), "verdict": "", "summary": ""})
        job["status"] = "reviewing"; job["updated"] = _now(); _write(job)
    log = (_job_dir(job_id) / f"review-{provider}.log").open("a")
    process = Popen([sys.executable, str(MANAGER), "review-worker", job_id, provider],
                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                    start_new_session=True, close_fds=True)
    log.close()
    return public_job(_read(job_id)) | {"review_pid": process.pid}


def review_worker(job_id: str, provider: str) -> None:
    try:
        job = _read(job_id)
        result = _run_agent(job, provider, review=True)
        text = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()[-60000:]
        verdicts = re.findall(r"(?im)^\s*VERDICT:\s*(APPROVE|REVISE)\s*$", text)
        verdict = "approved" if result.returncode == 0 and verdicts and verdicts[-1].upper() == "APPROVE" else "revise"
        with _locked(job_id):
            job = _read(job_id)
            for row in reversed(job["reviews"]):
                if row["provider"] == provider and row["status"] == "running":
                    row.update(status=verdict, verdict=verdict, summary=text, finished=_now()); break
            job["status"] = "reviewed" if verdict == "approved" else "ready"
            job["updated"] = _now(); _write(job)
    except Exception as exc:
        with _locked(job_id):
            job = _read(job_id)
            for row in reversed(job["reviews"]):
                if row["provider"] == provider and row["status"] == "running":
                    row.update(status="failed", summary=str(exc)[:500], finished=_now()); break
            job["status"] = "ready"; job["updated"] = _now(); _write(job)


def _require_yes(value: bool) -> None:
    if not value:
        raise SystemExit("Refusing: this action requires --yes from the human-facing nbshell UI or CLI")


def apply_job(job_id: str, yes: bool) -> dict:
    _require_yes(yes)
    with _locked(job_id):
        job = _read(job_id)
        if job["status"] != "reviewed" or not any(r.get("status") == "approved" for r in job["reviews"]):
            raise SystemExit("A different provider must approve the job before it can be applied")
        repo = Path(job["repository"])
        if _git(repo, "rev-parse", "HEAD").stdout.strip() != job["base"]:
            raise SystemExit("Source branch moved since job creation; create a fresh job or rebase manually")
        if _git(repo, "status", "--porcelain").stdout.strip():
            raise SystemExit("Source repository is not clean")
        fetch = _git(repo, "fetch", "--no-tags", str(_workspace(job_id)), job["commit"], timeout=120, check=False)
        if fetch.returncode:
            raise SystemExit("Could not import the reviewed transaction commit")
        result = _git(repo, "cherry-pick", "FETCH_HEAD", timeout=120, check=False)
        if result.returncode:
            _git(repo, "cherry-pick", "--abort", check=False)
            raise SystemExit("Cherry-pick conflicted and was aborted")
        job["status"] = "applied"; job["updated"] = _now()
        job["actions"].append({"action": "apply", "timestamp": _now(), "commit": _git(repo, "rev-parse", "HEAD").stdout.strip()})
        _write(job)
    return public_job(job)


def install_job(job_id: str, yes: bool) -> dict:
    _require_yes(yes)
    with _locked(job_id):
        job = _read(job_id)
        if job["status"] not in {"applied", "installed"}:
            raise SystemExit("Apply the reviewed job before installation")
        installer = Path(job["repository"]) / "install.sh"
        if not installer.is_file() or not os.access(installer, os.X_OK):
            raise SystemExit("Repository has no executable install.sh")
        result = subprocess.run([str(installer)], cwd=job["repository"], text=True, capture_output=True, timeout=900, check=False)
        (_job_dir(job_id) / "install.log").write_text((result.stdout + result.stderr)[-60000:])
        if result.returncode:
            raise SystemExit(f"Installer exited with code {result.returncode}")
        job["status"] = "installed"; job["updated"] = _now(); job["actions"].append({"action": "install", "timestamp": _now()}); _write(job)
    return public_job(job)


def push_job(job_id: str, yes: bool) -> dict:
    _require_yes(yes)
    with _locked(job_id):
        job = _read(job_id)
        if job["status"] not in {"applied", "installed"}:
            raise SystemExit("Apply the reviewed job before pushing")
        repo = Path(job["repository"])
        if _git(repo, "branch", "--show-current").stdout.strip() != job["branch"]:
            raise SystemExit("Source repository is no longer on the original branch")
        result = _git(repo, "push", "origin", job["branch"], timeout=180, check=False)
        if result.returncode:
            raise SystemExit((result.stderr or "Push failed").strip().splitlines()[-1])
        job["status"] = "pushed"; job["updated"] = _now(); job["actions"].append({"action": "push", "timestamp": _now()}); _write(job)
    return public_job(job)


def reject_job(job_id: str, yes: bool) -> dict:
    _require_yes(yes)
    with _locked(job_id):
        job = _read(job_id)
        if job["status"] in {"applied", "installed", "pushed"}:
            raise SystemExit("Applied jobs cannot be rejected automatically")
        job["status"] = "rejected"; job["updated"] = _now(); job["actions"].append({"action": "reject", "timestamp": _now()}); _write(job)
    shutil.rmtree(DATA_ROOT / job_id, ignore_errors=True)
    return public_job(job)


def public_job(job: dict, detail: bool = False) -> dict:
    result = {key: job.get(key) for key in (
        "id", "provider", "repository", "branch", "base", "task", "status", "created",
        "updated", "commit", "summary", "error", "actions",
    )}
    reviews = job.get("reviews", [])
    result["reviews"] = reviews if detail else [{
        key: row.get(key) for key in ("provider", "status", "verdict", "started", "finished")
    } for row in reviews]
    if not detail:
        result["task"] = str(result.get("task") or "")[:1200]
        result["summary"] = str(result.get("summary") or "")[:1200]
        result["error"] = str(result.get("error") or "")[:500]
    result["can_review"] = job.get("status") in {"ready", "reviewed"}
    result["can_apply"] = job.get("status") == "reviewed" and any(r.get("status") == "approved" for r in job.get("reviews", []))
    result["can_install"] = job.get("status") in {"applied", "installed"} and (Path(job["repository"]) / "install.sh").is_file()
    result["can_push"] = job.get("status") in {"applied", "installed"}
    if detail and job.get("commit") and _workspace(job["id"]).is_dir():
        result["diff"] = _git(_workspace(job["id"]), "diff", "--no-ext-diff", f"{job['base']}..{job['commit']}", timeout=60).stdout[-120000:]
    return result


def list_jobs(detail_id: str = "") -> dict:
    if detail_id:
        return public_job(_read(detail_id), detail=True)
    rows = []
    if STATE_ROOT.is_dir():
        for path in STATE_ROOT.iterdir():
            try:
                rows.append(public_job(json.loads((path / "job.json").read_text())))
            except (OSError, json.JSONDecodeError):
                continue
    rows.sort(key=lambda row: row.get("created", 0), reverse=True)
    return {"jobs": rows[:20], "running": sum(row["status"] in {"queued", "preparing", "running", "reviewing"} for row in rows)}


def main() -> int:
    parser = argparse.ArgumentParser(description="nbshell transactional Hermes jobs")
    sub = parser.add_subparsers(dest="command", required=True)
    create_p = sub.add_parser("create"); create_p.add_argument("provider", choices=sorted(PROVIDERS)); create_p.add_argument("repository"); create_p.add_argument("task")
    worker_p = sub.add_parser("worker"); worker_p.add_argument("job_id")
    review_p = sub.add_parser("review"); review_p.add_argument("job_id"); review_p.add_argument("provider", choices=sorted(PROVIDERS))
    review_worker_p = sub.add_parser("review-worker"); review_worker_p.add_argument("job_id"); review_worker_p.add_argument("provider", choices=sorted(PROVIDERS))
    list_p = sub.add_parser("list"); list_p.add_argument("--job", default="")
    for name in ("apply", "install", "push", "reject"):
        action = sub.add_parser(name); action.add_argument("job_id"); action.add_argument("--yes", action="store_true")
    args = parser.parse_args()
    if args.command == "create": result = create(args.provider, args.repository, args.task)
    elif args.command == "worker": worker(args.job_id); return 0
    elif args.command == "review": result = start_review(args.job_id, args.provider)
    elif args.command == "review-worker": review_worker(args.job_id, args.provider); return 0
    elif args.command == "list": result = list_jobs(args.job)
    elif args.command == "apply": result = apply_job(args.job_id, args.yes)
    elif args.command == "install": result = install_job(args.job_id, args.yes)
    elif args.command == "push": result = push_job(args.job_id, args.yes)
    else: result = reject_job(args.job_id, args.yes)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
