#!/usr/bin/env python3
"""Persistent, human-approved multi-agent teams for nbshell.

Hermes supplies a bounded plan. This coordinator runs each task through the
transaction manager, requests an independent review, retries requested
revisions, and integrates only approved commits in a disposable clone.
"""

from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from subprocess import Popen


STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell/hermes-teams"
DATA_ROOT = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nbshell/hermes-teams"
JOB_MANAGER = Path(os.environ.get("NBSHELL_HERMES_JOB_MANAGER", Path.home() / ".local/share/nbshell/hermes-jobs/manager.py"))
MANAGER = Path(__file__).resolve()
PROVIDERS = ("codex", "claude", "gemini")
ACTIVE = {"planning", "running", "reviewing", "revising", "integrating", "testing"}
FINAL = {"applied", "installed", "pushed", "rejected", "cancelled"}
MAX_TASKS = 3
MAX_REVISIONS = 2
MAX_RUNTIME = 3 * 60 * 60
MAX_TEXT = 12_000
ALLOWED_CHECKS = {"pytest", "python", "python3", "npm", "pnpm", "cargo", "go", "make", "shellcheck"}
SECRET = re.compile(r"(?:BEGIN [A-Z ]*PRIVATE KEY|\b(?:sk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{16,}|(?:password|api[_ -]?key|token)\s*[:=]\s*\S+)", re.I)


def _now() -> int: return int(time.time())


def _id(value: str) -> str:
    if not re.fullmatch(r"[a-z0-9-]{8,40}", value): raise SystemExit("Invalid team id")
    return value


def _dir(team_id: str) -> Path: return STATE_ROOT / _id(team_id)
def _workspace(team_id: str) -> Path: return DATA_ROOT / _id(team_id) / "integration"


def _read(team_id: str) -> dict:
    try: return json.loads((_dir(team_id) / "team.json").read_text())
    except (OSError, json.JSONDecodeError) as exc: raise SystemExit(f"Unknown or damaged team: {team_id}") from exc


def _write(team: dict) -> None:
    path = _dir(team["id"]); path.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path / "team.tmp"; tmp.write_text(json.dumps(team, indent=2, sort_keys=True) + "\n"); os.chmod(tmp, 0o600)
    tmp.replace(path / "team.json")


@contextmanager
def _locked(team_id: str):
    path = _dir(team_id); path.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (path / ".lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX); yield


@contextmanager
def _admission_locked():
    STATE_ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE_ROOT / ".admission.lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX); yield


def _process_start(pid: int) -> str:
    if pid <= 1: return ""
    try: return Path(f"/proc/{pid}/stat").read_text().rpartition(") ")[2].split()[19]
    except (OSError, IndexError): return ""


def _process_alive(record: dict) -> bool:
    pid = int(record.get("pid") or 0); start = str(record.get("pid_start") or "")
    return bool(start) and _process_start(pid) == start


def _git(repo: Path, *args: str, timeout: int = 120, check: bool = True):
    return subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True, timeout=timeout, check=check)


def _jobs():
    spec = importlib.util.spec_from_file_location("nbshell_hermes_jobs", JOB_MANAGER)
    if not spec or not spec.loader: raise SystemExit("Hermes transaction manager is unavailable")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def _safe_text(value, label: str) -> str:
    text = str(value or "").strip()
    if not text or len(text) > MAX_TEXT or "\x00" in text or SECRET.search(text): raise SystemExit(f"Invalid or sensitive {label}")
    return text


def _plan(value: str) -> tuple[list[dict], list[list[str]]]:
    try: raw = json.loads(value)
    except json.JSONDecodeError as exc: raise SystemExit("Plan must be valid JSON") from exc
    tasks = raw.get("tasks", []); checks = raw.get("checks", [])
    if not 1 <= len(tasks) <= MAX_TASKS: raise SystemExit("A supervised team requires one to three tasks")
    rows = []
    for index, item in enumerate(tasks):
        provider = str(item.get("provider", ""))
        if provider not in PROVIDERS: raise SystemExit("Every task needs a valid provider")
        rows.append({"id": index + 1, "title": _safe_text(item.get("title"), "task title")[:160],
                     "instructions": _safe_text(item.get("instructions"), "task instructions"),
                     "provider": provider, "attempt": 0, "job_id": "", "history": [], "status": "queued"})
    safe_checks = []
    for command in checks[:5]:
        if not isinstance(command, list) or not command or str(command[0]) not in ALLOWED_CHECKS or len(command) > 16:
            raise SystemExit("Checks must be argument arrays using an approved test runner")
        safe_checks.append([str(part)[:500] for part in command])
    return rows, safe_checks


def _spawn(team_id: str) -> int:
    log = (_dir(team_id) / "coordinator.log").open("a")
    process = Popen([sys.executable, str(MANAGER), "coordinator", team_id], stdin=subprocess.DEVNULL,
                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
    log.close(); return process.pid


def create(repository: str, goal: str, plan_json: str) -> dict:
    jobs = _jobs(); repo, base, branch = jobs._repo_info(repository)
    goal = _safe_text(goal, "goal"); tasks, checks = _plan(plan_json)
    with _admission_locked():
        running = list_teams()["running"]
        if running: raise SystemExit("Only one supervised team may run at a time")
        team_id = time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3)
        team = {"schema": 1, "id": team_id, "repository": str(repo), "base": base, "branch": branch,
                "goal": goal, "status": "planning", "created": _now(), "updated": _now(), "started": _now(),
                "pid": 0, "pid_start": "", "launcher_pid": os.getpid(), "launcher_start": _process_start(os.getpid()),
                "tasks": tasks, "checks": checks, "check_results": [], "integration_commit": "",
                "summary": "Plan accepted; coordinator is starting", "error": "", "actions": []}
        _write(team)
    try: pid = _spawn(team_id)
    except Exception as exc:
        with _locked(team_id):
            team = _read(team_id); team.update(status="failed", error=str(exc)[:800], updated=_now()); _write(team)
        raise
    with _locked(team_id):
        team = _read(team_id)
        if team["status"] == "planning":
            team["pid"] = pid; team["pid_start"] = _process_start(pid); team["launcher_pid"] = 0; team["launcher_start"] = ""
            team["status"] = "running"; team["updated"] = _now(); _write(team)
    return public(team)


def _persist_active(team: dict) -> bool:
    with _locked(team["id"]):
        current = _read(team["id"])
        if current["status"] not in ACTIVE: return False
        if current.get("pid_start") and team.get("pid_start") and current["pid_start"] != team["pid_start"]: return False
        _write(team)
        return True


def _latest_job(task: dict, jobs):
    return jobs._read(task["job_id"]) if task.get("job_id") else None


def _start_task(team: dict, task: dict, feedback: str = "") -> bool:
    jobs = _jobs()
    with _locked(team["id"]):
        current = _read(team["id"])
        if current["status"] not in ACTIVE:
            return False
        if current.get("pid_start") and team.get("pid_start") and current["pid_start"] != team["pid_start"]:
            return False
        current_task = next(row for row in current["tasks"] if row["id"] == task["id"])
        current_task["attempt"] += 1
        prompt = f"TEAM GOAL:\n{current['goal']}\n\nYOUR NON-OVERLAPPING TASK ({current_task['title']}):\n{current_task['instructions']}"
        if feedback: prompt += "\n\nINDEPENDENT REVIEW REQUESTED A REVISION:\n" + feedback[-6000:]
        result = jobs.create(current_task["provider"], current["repository"], prompt)
        current_task["job_id"] = result["id"]; current_task["status"] = "running"
        current_task["history"].append({"attempt": current_task["attempt"], "job_id": result["id"], "started": _now()})
        current["updated"] = _now(); _write(current)
        team.clear(); team.update(current)
        return True


def _reviewer(provider: str, attempt: int) -> str:
    others = [candidate for candidate in PROVIDERS if candidate != provider]
    return others[(attempt - 1) % len(others)]


def _integrate(team: dict) -> None:
    jobs = _jobs(); target = _workspace(team["id"])
    if target.exists(): shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    subprocess.run(["git", "clone", "--no-hardlinks", "--no-checkout", team["repository"], str(target)], check=True, capture_output=True, timeout=180)
    _git(target, "checkout", "--detach", team["base"]); _git(target, "config", "user.name", "nbshell Hermes Team"); _git(target, "config", "user.email", "noreply@nbshell.local")
    for task in team["tasks"]:
        job = jobs._read(task["job_id"]); source = jobs._workspace(job["id"])
        _git(target, "fetch", "--no-tags", str(source), job["commit"])
        picked = _git(target, "cherry-pick", "FETCH_HEAD", check=False)
        if picked.returncode:
            repair = {"id": team["id"], "task": (
                "Resolve only the current Git cherry-pick conflicts in /workspace. Preserve the intent of both the already integrated work and this task: "
                + task["title"] + ". Inspect the conflict, edit the files, and run focused checks. Do not abort or finish the cherry-pick yourself.")}
            result = jobs._run_agent(repair, "codex", workspace_override=target)
            (_dir(team["id"]) / f"integration-repair-{task['id']}.log").write_text(((result.stdout or "") + (result.stderr or ""))[-60000:])
            _git(target, "add", "-A")
            continued = _git(target, "cherry-pick", "--continue", check=False)
            if result.returncode or continued.returncode:
                _git(target, "cherry-pick", "--abort", check=False)
                raise RuntimeError(f"Integration conflict in {task['title']} could not be resolved safely")
        task["status"] = "integrated"
    team["integration_commit"] = _git(target, "rev-parse", "HEAD").stdout.strip()


def _checks(team: dict) -> None:
    target = _workspace(team["id"]); team["check_results"] = []
    for command in team["checks"]:
        started = time.monotonic()
        sandbox = ["bwrap", "--die-with-parent", "--new-session", "--unshare-all", "--ro-bind", "/usr", "/usr",
                   "--ro-bind", "/etc", "/etc", "--ro-bind", "/opt", "/opt", "--proc", "/proc", "--dev", "/dev",
                   "--symlink", "usr/bin", "/bin", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
                   "--tmpfs", "/tmp", "--tmpfs", "/home", "--bind", str(target), "/workspace", "--chdir", "/workspace",
                   "--setenv", "HOME", "/tmp", "--setenv", "NO_COLOR", "1", "--setenv", "CI", "1"]
        result = subprocess.run(sandbox + command, text=True, capture_output=True, timeout=900, check=False)
        row = {"command": command, "returncode": result.returncode, "seconds": round(time.monotonic() - started, 2),
               "output": ((result.stdout or "") + (result.stderr or ""))[-6000:]}
        team["check_results"].append(row)
        if result.returncode: raise RuntimeError("Integration check failed: " + " ".join(command))


def coordinator(team_id: str) -> None:
    jobs = _jobs()
    try:
        with _locked(team_id):
            team = _read(team_id)
            if team["status"] not in ACTIVE: return
            pid = int(team.get("pid") or 0)
            if pid and pid != os.getpid(): return
            if not pid and not _process_alive({"pid": team.get("launcher_pid", 0), "pid_start": team.get("launcher_start", "")}): return
            team.update(pid=os.getpid(), pid_start=_process_start(os.getpid()), launcher_pid=0, launcher_start="",
                        status="running" if team["status"] == "planning" else team["status"], updated=_now()); _write(team)
        while True:
            with _locked(team_id): team = _read(team_id)
            if team["status"] in FINAL | {"paused", "awaiting_approval", "failed"}: return
            if _now() - team["started"] > MAX_RUNTIME: raise RuntimeError("Team exceeded its three-hour runtime limit")
            changed = False
            for task in team["tasks"]:
                if task["status"] == "queued":
                    if not _start_task(team, task): return
                    changed = True; continue
                if task["status"] in {"integrated", "approved", "failed"}: continue
                job = _latest_job(task, jobs)
                if not job: continue
                status = job["status"]
                if status in {"queued", "preparing", "running", "reviewing"} and job.get("pid") and not jobs._process_alive(job):
                    if task["attempt"] > MAX_REVISIONS: raise RuntimeError(f"{task['title']}: recovery limit reached")
                    if not _start_task(team, task, "The previous worker stopped during suspend, reboot, or process termination. Resume the task from its original specification."): return
                    changed = True; continue
                if status in {"failed", "no_changes", "rejected"}:
                    task["status"] = "failed"; raise RuntimeError(f"{task['title']}: transaction ended as {status}")
                if status == "ready":
                    latest = job.get("reviews", [])[-1] if job.get("reviews") else {}
                    if latest.get("status") == "revise":
                        if task["attempt"] > MAX_REVISIONS: raise RuntimeError(f"{task['title']}: revision limit reached")
                        task["status"] = "revising"
                        if not _start_task(team, task, latest.get("summary", "")): return
                        changed = True
                    elif not any(row.get("status") == "running" for row in job.get("reviews", [])):
                        reviewer = _reviewer(task["provider"], task["attempt"])
                        jobs.start_review(job["id"], reviewer)
                        task["history"][-1]["reviewer"] = reviewer
                        task["status"] = "reviewing"; changed = True
                elif status == "reviewed": task["status"] = "approved"; changed = True
                else: task["status"] = status
            if all(task["status"] == "approved" for task in team["tasks"]):
                team["status"] = "integrating"; team["summary"] = "All tasks approved; integrating isolated commits"
                if not _persist_active(team): return
                _integrate(team); team["status"] = "testing"
                if not _persist_active(team): return
                _checks(team)
                team["status"] = "awaiting_approval"; team["summary"] = "Team result reviewed, integrated, and checked; human approval required"
                changed = True
            else:
                states = {task["status"] for task in team["tasks"]}
                team["status"] = "reviewing" if "reviewing" in states else ("revising" if "revising" in states else "running")
            if changed or True:
                team["updated"] = _now(); team["pid"] = os.getpid(); team["pid_start"] = _process_start(os.getpid())
                if not _persist_active(team): return
            if team["status"] == "awaiting_approval": return
            time.sleep(2)
    except (Exception, SystemExit) as exc:
        with _locked(team_id):
            team = _read(team_id)
            if team["status"] in ACTIVE:
                team.update(status="failed", error=str(exc)[:800], summary="Team stopped before source application", pid=0, pid_start="", updated=_now()); _write(team)


def control(team_id: str, action: str, yes: bool = False) -> dict:
    with _locked(team_id):
        team = _read(team_id)
        if action in {"apply", "install", "push", "reject"} and not yes: raise SystemExit("Refusing: this action requires --yes from the human-facing UI or CLI")
        if action == "pause":
            if team["status"] not in ACTIVE: raise SystemExit("Team is not active")
            team["status"] = "paused"; team["summary"] = "Paused; already-running isolated jobs may finish safely"
        elif action == "resume":
            if team["status"] not in {"paused", "failed"}: raise SystemExit("Only paused or failed teams can resume")
            team["status"] = "running"; team["error"] = ""; team["pid"] = _spawn(team_id); team["pid_start"] = _process_start(team["pid"])
        elif action == "cancel":
            jobs = _jobs()
            jobs._terminate_process(team)
            for task in team.get("tasks", []):
                if not task.get("job_id"): continue
                try:
                    job = jobs._read(task["job_id"])
                    jobs._terminate_process(job)
                    with jobs._locked(job["id"]):
                        job = jobs._read(job["id"]); job.update(status="rejected", pid=0, pid_start="", updated=_now(), error="Cancelled by supervised team owner"); jobs._write(job)
                except (OSError, SystemExit): pass
            team["status"] = "cancelled"; team["summary"] = "Cancelled without changing the source repository"
        elif action == "reject":
            if team["status"] in {"applied", "installed", "pushed"}: raise SystemExit("An applied team cannot be rejected")
            jobs = _jobs(); jobs._terminate_process(team)
            for task in team.get("tasks", []):
                if not task.get("job_id"): continue
                try:
                    job = jobs._read(task["job_id"]); jobs._terminate_process(job)
                    with jobs._locked(job["id"]):
                        job = jobs._read(job["id"]); job.update(status="rejected", pid=0, pid_start="", updated=_now(), error="Rejected by supervised team owner"); jobs._write(job)
                except (OSError, SystemExit): pass
            team["status"] = "rejected"; shutil.rmtree(DATA_ROOT / team_id, ignore_errors=True)
        elif action == "apply":
            if team["status"] != "awaiting_approval": raise SystemExit("Team is not ready for human approval")
            repo = Path(team["repository"])
            if _git(repo, "rev-parse", "HEAD").stdout.strip() != team["base"] or _git(repo, "status", "--porcelain").stdout.strip():
                raise SystemExit("Source repository moved or is dirty; no changes were applied")
            _git(repo, "fetch", "--no-tags", str(_workspace(team_id)), team["integration_commit"])
            result = _git(repo, "cherry-pick", f"{team['base']}..FETCH_HEAD", check=False)
            if result.returncode: _git(repo, "cherry-pick", "--abort", check=False); raise SystemExit("Team apply conflicted and was aborted")
            team["status"] = "applied"
        elif action == "install":
            if team["status"] not in {"applied", "installed"}: raise SystemExit("Apply before installation")
            installer = Path(team["repository"]) / "install.sh"
            if not installer.is_file(): raise SystemExit("Repository has no install.sh")
            result = subprocess.run([str(installer)], cwd=team["repository"], timeout=900, check=False)
            if result.returncode: raise SystemExit(f"Installer exited with {result.returncode}")
            team["status"] = "installed"
        elif action == "push":
            if team["status"] not in {"applied", "installed"}: raise SystemExit("Apply before push")
            result = _git(Path(team["repository"]), "push", "origin", team["branch"], timeout=180, check=False)
            if result.returncode: raise SystemExit((result.stderr or "Push failed").splitlines()[-1])
            team["status"] = "pushed"
        else: raise SystemExit("Unknown team action")
        team["updated"] = _now(); team["actions"].append({"action": action, "timestamp": _now()}); _write(team)
    return public(team, True)


def public(team: dict, detail: bool = False) -> dict:
    result = {key: team.get(key) for key in ("id", "repository", "branch", "base", "goal", "status", "created", "updated", "summary", "error", "tasks", "checks", "check_results", "actions")}
    complete = sum(task.get("status") in {"approved", "integrated"} for task in team.get("tasks", []))
    result["progress"] = 100 if team.get("status") in {"awaiting_approval", "applied", "installed", "pushed"} else round(complete * 80 / max(1, len(team.get("tasks", []))))
    result["elapsed"] = max(0, _now() - team.get("started", team.get("created", _now())))
    result["agent_calls"] = sum(int(task.get("attempt", 0)) + sum(
        1 for item in task.get("history", []) if item.get("reviewer")) for task in team.get("tasks", []))
    result["can_apply"] = team.get("status") == "awaiting_approval"; result["can_install"] = team.get("status") in {"applied", "installed"}
    result["can_push"] = team.get("status") in {"applied", "installed"}; result["can_resume"] = team.get("status") in {"paused", "failed"}
    if detail and team.get("integration_commit") and _workspace(team["id"]).is_dir():
        result["diff"] = _git(_workspace(team["id"]), "diff", "--no-ext-diff", f"{team['base']}..{team['integration_commit']}").stdout[-120000:]
    return result


def list_teams(team_id: str = "") -> dict:
    def refreshed(current_id: str) -> dict:
        with _locked(current_id):
            team = _read(current_id)
            owner = team if team.get("pid") else {"pid": team.get("launcher_pid", 0), "pid_start": team.get("launcher_start", "")}
            if team.get("status") in ACTIVE and not _process_alive(owner):
                team.update(status="paused", error="Coordinator stopped; safe resume is available", summary="Interrupted without changing the source repository",
                            pid=0, pid_start="", launcher_pid=0, launcher_start="", updated=_now()); _write(team)
            return team

    if team_id:
        return public(refreshed(team_id), True)
    rows = []
    if STATE_ROOT.is_dir():
        for path in STATE_ROOT.iterdir():
            try:
                if path.is_dir():
                    rows.append(public(refreshed(path.name)))
            except (OSError, json.JSONDecodeError): pass
    rows.sort(key=lambda row: row.get("created", 0), reverse=True)
    return {"teams": rows[:10], "running": sum(row["status"] in ACTIVE for row in rows), "attention": sum(row["status"] in {"awaiting_approval", "failed"} for row in rows)}


def main() -> int:
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest="command", required=True)
    create_p = sub.add_parser("create"); create_p.add_argument("repository"); create_p.add_argument("goal"); create_p.add_argument("plan")
    worker = sub.add_parser("coordinator"); worker.add_argument("team_id")
    listing = sub.add_parser("list"); listing.add_argument("--team", default="")
    for name in ("pause", "resume", "cancel", "apply", "install", "push", "reject"):
        item = sub.add_parser(name); item.add_argument("team_id"); item.add_argument("--yes", action="store_true")
    args = parser.parse_args()
    if args.command == "create": result = create(args.repository, args.goal, args.plan)
    elif args.command == "coordinator": coordinator(args.team_id); return 0
    elif args.command == "list": result = list_teams(args.team)
    else: result = control(args.team_id, args.command, args.yes)
    print(json.dumps(result)); return 0


if __name__ == "__main__": raise SystemExit(main())
