#!/usr/bin/env python3
"""Reviewed Second Brain proposals with a human-only apply and push gate."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
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


STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell/hermes-brain"
DATA_ROOT = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nbshell/hermes-brain"
BRAIN_ROOT = Path(os.environ.get("NBSHELL_BRAIN_ROOT", Path.home() / "Sync/brain")).resolve()
JOB_MANAGER = Path(os.environ.get("NBSHELL_HERMES_JOB_MANAGER", Path.home() / ".local/share/nbshell/hermes-jobs/manager.py"))
MANAGER = Path(__file__).resolve()
PROVIDERS = {"codex", "claude", "gemini"}
ALLOWED_ROOTS = {"01_Projects", "02_Knowledge", "03_Daily", "04_Inbox"}
MAX_PROPOSAL = 48_000
MAX_REVISIONS = 2
MAX_CONCURRENT_REVIEWS = 2
SECRET = re.compile(r"(?:BEGIN [A-Z ]*PRIVATE KEY|\b(?:sk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{16,}|(?:password|passwd|api[_ -]?key|access[_ -]?token|refresh[_ -]?token)\s*[:=]\s*\S+)", re.I)


def _now() -> int: return int(time.time())


def _valid_id(value: str) -> str:
    if not re.fullmatch(r"[a-z0-9-]{8,40}", value): raise SystemExit("Invalid proposal id")
    return value


def _dir(proposal_id: str) -> Path: return STATE_ROOT / _valid_id(proposal_id)
def _workspace(proposal_id: str) -> Path: return DATA_ROOT / _valid_id(proposal_id) / "workspace"


def _jobs():
    spec = importlib.util.spec_from_file_location("nbshell_hermes_jobs", JOB_MANAGER)
    if not spec or not spec.loader: raise SystemExit("Hermes transaction manager is unavailable")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def _git(repo: Path, *args: str, timeout: int = 120, check: bool = True):
    return subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True, timeout=timeout, check=check)


def _read(proposal_id: str) -> dict:
    try: return json.loads((_dir(proposal_id) / "proposal.json").read_text())
    except (OSError, json.JSONDecodeError) as exc: raise SystemExit(f"Unknown or damaged proposal: {proposal_id}") from exc


def _write(proposal: dict) -> None:
    directory = _dir(proposal["id"]); directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = directory / "proposal.tmp"; temporary.write_text(json.dumps(proposal, indent=2, sort_keys=True) + "\n"); os.chmod(temporary, 0o600)
    temporary.replace(directory / "proposal.json")


@contextmanager
def _locked(proposal_id: str):
    directory = _dir(proposal_id); directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / ".lock").open("a") as handle:
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


def _target(value: str) -> tuple[str, Path]:
    relative = Path(str(value or ""))
    if relative.is_absolute() or ".." in relative.parts or len(relative.parts) < 2 or relative.parts[0] not in ALLOWED_ROOTS or relative.suffix != ".md":
        raise SystemExit("Target must be a Markdown note below 01_Projects, 02_Knowledge, 03_Daily, or 04_Inbox")
    target = (BRAIN_ROOT / relative).resolve(strict=False)
    if BRAIN_ROOT not in target.parents: raise SystemExit("Target escapes the Second Brain")
    if target.exists() and target.is_symlink(): raise SystemExit("Symlink targets are not allowed")
    return relative.as_posix(), target


def _safe_markdown(value: str) -> str:
    text = str(value or "")
    if not text.strip() or len(text) > MAX_PROPOSAL or "\x00" in text or SECRET.search(text):
        raise SystemExit("Proposal is empty, too large, or appears to contain credentials")
    return text if text.endswith("\n") else text + "\n"


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "absent"


def _prepare_workspace(proposal_id: str, relative: str, markdown: str, mode: str) -> tuple[str, str]:
    workspace = _workspace(proposal_id)
    if workspace.exists(): shutil.rmtree(workspace)
    workspace.mkdir(parents=True, mode=0o700)
    _git(workspace, "init", "-b", "proposal"); _git(workspace, "config", "user.name", "nbshell Brain Proposal"); _git(workspace, "config", "user.email", "noreply@nbshell.local")
    staged = workspace / relative; staged.parent.mkdir(parents=True, exist_ok=True)
    # Never copy vault content into a provider-visible workspace. Reviewers see
    # only the proposed addition/new note and its declared destination.
    staged.write_text("")
    _git(workspace, "add", "-A"); _git(workspace, "commit", "-m", "Record proposal baseline")
    base = _git(workspace, "rev-parse", "HEAD").stdout.strip()
    staged.write_text(markdown)
    _git(workspace, "add", "-A"); _git(workspace, "commit", "-m", f"Propose Second Brain update: {relative}")
    return base, _git(workspace, "rev-parse", "HEAD").stdout.strip()


def _spawn_review(proposal_id: str) -> int:
    log = (_dir(proposal_id) / "review.log").open("a")
    process = Popen([sys.executable, str(MANAGER), "review-worker", proposal_id], stdin=subprocess.DEVNULL,
                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
    log.close(); return process.pid


def create(target: str, markdown: str, mode: str, author: str, reviewer: str, rationale: str) -> dict:
    if author not in PROVIDERS or reviewer not in PROVIDERS or author == reviewer: raise SystemExit("Author and reviewer must be different supported providers")
    relative, target_path = _target(target); markdown = _safe_markdown(markdown)
    if mode not in {"append", "create"}: raise SystemExit("Proposal mode must be append or create")
    if mode == "append" and not target_path.is_file(): raise SystemExit("Append mode requires an existing note")
    if mode == "create" and target_path.exists(): raise SystemExit("Create mode refuses to replace an existing note")
    if len(str(rationale or "")) > 2000 or SECRET.search(str(rationale or "")): raise SystemExit("Invalid or sensitive rationale")
    if not (BRAIN_ROOT / ".git").is_dir(): raise SystemExit("Second Brain is not an available Git repository")
    with _admission_locked():
        if list_proposals().get("reviewing", 0) >= MAX_CONCURRENT_REVIEWS: raise SystemExit("At most two Brain proposals may be reviewed concurrently")
        proposal_id = time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3)
        base, commit = _prepare_workspace(proposal_id, relative, markdown, mode)
        proposal = {"schema": 1, "id": proposal_id, "target": relative, "target_digest": _digest(target_path),
                    "brain_base": _git(BRAIN_ROOT, "rev-parse", "HEAD").stdout.strip(), "mode": mode, "author": author, "reviewer": reviewer,
                    "rationale": str(rationale or "")[:2000], "status": "reviewing", "revision": 0, "workspace_base": base,
                    "commit": commit, "created": _now(), "updated": _now(), "review": "", "error": "", "actions": [],
                    "pid": 0, "pid_start": "", "launcher_pid": os.getpid(), "launcher_start": _process_start(os.getpid())}
        _write(proposal)
    try: pid = _spawn_review(proposal_id)
    except Exception as exc:
        with _locked(proposal_id):
            proposal = _read(proposal_id); proposal.update(status="failed", error=str(exc)[:800], updated=_now()); _write(proposal)
        raise
    with _locked(proposal_id):
        proposal = _read(proposal_id)
        if proposal["status"] == "reviewing":
            proposal["pid"] = pid; proposal["pid_start"] = _process_start(pid)
            proposal["launcher_pid"] = 0; proposal["launcher_start"] = ""; _write(proposal)
    return public(proposal)


def revise(proposal_id: str, markdown: str) -> dict:
    markdown = _safe_markdown(markdown)
    with _locked(proposal_id):
        proposal = _read(proposal_id)
        if proposal["status"] != "revision_requested": raise SystemExit("Proposal is not awaiting a revision")
        if proposal["revision"] >= MAX_REVISIONS: raise SystemExit("Proposal revision limit reached")
        proposal["revision"] += 1
        base, commit = _prepare_workspace(proposal_id, proposal["target"], markdown, proposal["mode"])
        proposal.update(workspace_base=base, commit=commit, status="reviewing", review="", error="",
                        pid=0, pid_start="", launcher_pid=os.getpid(), launcher_start=_process_start(os.getpid()), updated=_now())
        _write(proposal)
        try:
            proposal["pid"] = _spawn_review(proposal_id)
        except Exception as exc:
            retryable = proposal["revision"] < MAX_REVISIONS
            proposal.update(status="revision_requested" if retryable else "failed", error=str(exc)[:800],
                            pid=0, pid_start="", launcher_pid=0, launcher_start="", updated=_now())
            _write(proposal)
            raise
        proposal["pid_start"] = _process_start(proposal["pid"])
        proposal["launcher_pid"] = 0; proposal["launcher_start"] = ""; _write(proposal)
    return public(proposal)


def review_worker(proposal_id: str) -> None:
    try:
        with _locked(proposal_id):
            proposal = _read(proposal_id)
            if proposal["status"] != "reviewing": return
            pid = int(proposal.get("pid") or 0)
            if pid and pid != os.getpid(): return
            if not pid and not _process_alive({"pid": proposal.get("launcher_pid", 0), "pid_start": proposal.get("launcher_start", "")}): return
            proposal.update(pid=os.getpid(), pid_start=_process_start(os.getpid()), launcher_pid=0, launcher_start="", updated=_now()); _write(proposal)
        jobs = _jobs()
        task = ("Review this proposed update to the user's Second Brain. The workspace contains only the target note, not the full vault. "
                "Check that the change records confirmed facts, distinguishes decisions from assumptions, contains no credentials or unnecessary personal data, follows Markdown structure, and stays within the stated rationale. "
                "Do not edit. End with VERDICT: APPROVE or VERDICT: REVISE.\n\nTARGET: " + proposal["target"] + "\nRATIONALE: " + proposal["rationale"])
        result = jobs._run_agent({"id": proposal_id, "task": task}, proposal["reviewer"], review=True, workspace_override=_workspace(proposal_id))
        output = ((result.stdout or "") + "\n" + (result.stderr or ""))[-60000:]
        verdicts = re.findall(r"(?im)^\s*VERDICT:\s*(APPROVE|REVISE)\s*$", output)
        status = "awaiting_approval" if result.returncode == 0 and verdicts and verdicts[-1].upper() == "APPROVE" else "revision_requested"
        with _locked(proposal_id):
            proposal = _read(proposal_id)
            if proposal["status"] != "reviewing": return
            proposal.update(status=status, review=output, pid=0, pid_start="", updated=_now()); _write(proposal)
    except (Exception, SystemExit) as exc:
        with _locked(proposal_id):
            proposal = _read(proposal_id)
            if proposal["status"] == "reviewing":
                proposal.update(status="failed", error=str(exc)[:800], pid=0, pid_start="", updated=_now()); _write(proposal)


def _require_yes(yes: bool) -> None:
    if not yes: raise SystemExit("Refusing: this action requires --yes from the human-facing UI or CLI")


def control(proposal_id: str, action: str, yes: bool) -> dict:
    _require_yes(yes)
    with _locked(proposal_id):
        proposal = _read(proposal_id); relative, target = _target(proposal["target"])
        if action == "apply":
            if proposal["status"] != "awaiting_approval": raise SystemExit("Proposal has not passed independent review")
            if _git(BRAIN_ROOT, "rev-parse", "HEAD").stdout.strip() != proposal["brain_base"]: raise SystemExit("Second Brain moved since proposal creation")
            if _digest(target) != proposal["target_digest"]: raise SystemExit("Target note changed since proposal creation")
            if _git(BRAIN_ROOT, "diff", "--quiet", "--", relative, check=False).returncode or _git(BRAIN_ROOT, "diff", "--cached", "--quiet", "--", relative, check=False).returncode:
                raise SystemExit("Target note has uncommitted changes")
            proposed = (_workspace(proposal_id) / relative).read_text()
            previous = target.read_bytes() if target.is_file() else None
            content = target.read_text().rstrip() + "\n\n" + proposed if proposal["mode"] == "append" else proposed
            target.parent.mkdir(parents=True, exist_ok=True); temporary = target.with_suffix(".nbshell-proposal.tmp")
            temporary.write_text(content); temporary.replace(target)
            result = _git(BRAIN_ROOT, "add", "--", relative, check=False)
            commit = _git(BRAIN_ROOT, "commit", "--only", "-m", f"docs: apply reviewed Hermes proposal for {Path(relative).stem}", "--", relative, check=False)
            if result.returncode or commit.returncode:
                if previous is None: target.unlink(missing_ok=True)
                else: target.write_bytes(previous)
                _git(BRAIN_ROOT, "reset", "HEAD", "--", relative, check=False)
                raise SystemExit((commit.stderr or result.stderr or "Could not commit proposal").strip().splitlines()[-1])
            proposal["status"] = "applied"; proposal["brain_commit"] = _git(BRAIN_ROOT, "rev-parse", "HEAD").stdout.strip()
        elif action == "push":
            if proposal["status"] != "applied": raise SystemExit("Apply the proposal before pushing")
            branch = _git(BRAIN_ROOT, "branch", "--show-current").stdout.strip()
            pushed = _git(BRAIN_ROOT, "push", "origin", branch, timeout=180, check=False)
            if pushed.returncode: raise SystemExit((pushed.stderr or "Push failed").strip().splitlines()[-1])
            proposal["status"] = "pushed"
        elif action == "reject":
            if proposal["status"] in {"applied", "pushed"}: raise SystemExit("Applied proposals cannot be rejected")
            if proposal.get("pid"): _jobs()._terminate_process(proposal)
            proposal["status"] = "rejected"; shutil.rmtree(DATA_ROOT / proposal_id, ignore_errors=True)
        else: raise SystemExit("Unknown proposal action")
        proposal["updated"] = _now(); proposal["actions"].append({"action": action, "timestamp": _now()}); _write(proposal)
    return public(proposal, True)


def public(proposal: dict, detail: bool = False) -> dict:
    result = {key: proposal.get(key) for key in ("id", "target", "mode", "author", "reviewer", "rationale", "status", "revision", "created", "updated", "review", "error", "actions")}
    if not detail: result["review"] = str(result.get("review") or "")[-1000:]
    result["can_apply"] = proposal.get("status") == "awaiting_approval"; result["can_push"] = proposal.get("status") == "applied"
    result["can_revise"] = proposal.get("status") == "revision_requested" and proposal.get("revision", 0) < MAX_REVISIONS
    if detail and _workspace(proposal["id"]).is_dir():
        result["diff"] = _git(_workspace(proposal["id"]), "diff", "--no-ext-diff", f"{proposal['workspace_base']}..{proposal['commit']}").stdout[-120000:]
    return result


def list_proposals(proposal_id: str = "") -> dict:
    def refreshed(current_id: str) -> dict:
        with _locked(current_id):
            proposal = _read(current_id)
            owner = proposal if proposal.get("pid") else {"pid": proposal.get("launcher_pid", 0), "pid_start": proposal.get("launcher_start", "")}
            if proposal.get("status") == "reviewing" and not _process_alive(owner):
                proposal.update(status="revision_requested" if proposal.get("revision", 0) < MAX_REVISIONS else "failed",
                                error="Reviewer stopped; submit a safe revision to retry" if proposal.get("revision", 0) < MAX_REVISIONS else "Reviewer stopped after the final revision",
                                pid=0, pid_start="", launcher_pid=0, launcher_start="", updated=_now()); _write(proposal)
            return proposal

    if proposal_id:
        return public(refreshed(proposal_id), True)
    rows = []
    if STATE_ROOT.is_dir():
        for path in STATE_ROOT.iterdir():
            try:
                if path.is_dir():
                    rows.append(public(refreshed(path.name)))
            except (OSError, json.JSONDecodeError): pass
    rows.sort(key=lambda row: row.get("created", 0), reverse=True)
    return {"proposals": rows[:10], "reviewing": sum(row["status"] == "reviewing" for row in rows),
            "attention": sum(row["status"] in {"awaiting_approval", "revision_requested", "failed"} for row in rows)}


def main() -> int:
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest="command", required=True)
    create_p = sub.add_parser("create"); create_p.add_argument("target"); create_p.add_argument("markdown"); create_p.add_argument("mode", choices=["append", "create"]); create_p.add_argument("author"); create_p.add_argument("reviewer"); create_p.add_argument("rationale")
    revise_p = sub.add_parser("revise"); revise_p.add_argument("proposal_id"); revise_p.add_argument("markdown")
    worker = sub.add_parser("review-worker"); worker.add_argument("proposal_id")
    listing = sub.add_parser("list"); listing.add_argument("--proposal", default="")
    for name in ("apply", "push", "reject"):
        item = sub.add_parser(name); item.add_argument("proposal_id"); item.add_argument("--yes", action="store_true")
    args = parser.parse_args()
    if args.command == "create": result = create(args.target, args.markdown, args.mode, args.author, args.reviewer, args.rationale)
    elif args.command == "revise": result = revise(args.proposal_id, args.markdown)
    elif args.command == "review-worker": review_worker(args.proposal_id); return 0
    elif args.command == "list": result = list_proposals(args.proposal)
    else: result = control(args.proposal_id, args.command, args.yes)
    print(json.dumps(result)); return 0


if __name__ == "__main__": raise SystemExit(main())
