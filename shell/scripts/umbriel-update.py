#!/usr/bin/env python3
"""Check and update the user-local Umbriel compositor stack."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import tempfile

import subprocess
import sys

PROJECTS = (
    ("umbriel", "https://github.com/noctalia-dev/umbriel.git"),
    ("xdg-desktop-portal-umbriel", "https://github.com/noctalia-dev/xdg-desktop-portal-umbriel.git"),
)
PREFIX = pathlib.Path(os.environ.get("NBSHELL_UMBRIEL_PREFIX", "/usr/local"))
INSTALL_TREE = pathlib.Path(__file__).with_name("install-tree-transaction.py")
REVISION_RE = re.compile(r"[0-9a-f]{40}")


def source_root() -> pathlib.Path | None:
    configured = os.environ.get("NBSHELL_UMBRIEL_SOURCE_DIR")
    candidates = ([pathlib.Path(configured).expanduser()] if configured else []) + [
        pathlib.Path.home() / "projects",
        pathlib.Path.home() / ".cache/nbshell/umbriel-sources",
    ]
    for candidate in candidates:
        if all((candidate / name / ".git").exists() for name, _ in PROJECTS):
            return candidate
    return None


def git(path: pathlib.Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(["git", "-C", str(path), *args], text=True, capture_output=True, check=check)
    return result.stdout.strip()


def canonical_remote(value: str) -> str:
    value = value.removesuffix(".git").rstrip("/")
    if value.startswith("git@github.com:"):
        value = "https://github.com/" + value.split(":", 1)[1]
    return value


def remote_head(remote: str) -> str:
    result = subprocess.run(
        ["git", "ls-remote", remote, "HEAD"], text=True,
        capture_output=True, check=True, timeout=20,
    )
    fields = result.stdout.strip().split()
    if len(fields) != 2 or fields[1] != "HEAD" or REVISION_RE.fullmatch(fields[0]) is None:
        raise RuntimeError("remote returned an invalid HEAD revision")
    return fields[0]


def is_ancestor(path: pathlib.Path, older: str, newer: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(path), "merge-base", "--is-ancestor", older, newer],
        capture_output=True,
    )
    if result.returncode not in (0, 1):
        raise subprocess.CalledProcessError(result.returncode, result.args, result.stdout, result.stderr)
    return result.returncode == 0


def project_status(path: pathlib.Path, expected_remote: str, fetch: bool = True) -> dict:
    current = git(path, "rev-parse", "HEAD")
    remote = git(path, "remote", "get-url", "origin")
    expected = canonical_remote(expected_remote)
    if canonical_remote(remote) != expected:
        return {"current": current[:8], "latest": "", "available": False, "clean": False,
                "target": "", "error": f"unexpected origin: {remote}"}
    status_lines = git(path, "status", "--porcelain").splitlines()
    clean = not status_lines
    changes = [line.split(maxsplit=1)[1] if len(line.split(maxsplit=1)) == 2 else line
               for line in status_lines]
    latest = current
    error = ""
    blocked_reason = ""
    branch = git(path, "branch", "--show-current") or "detached HEAD"
    ahead = behind = 0
    if fetch:
        try:
            latest = remote_head(expected_remote)
            if latest != current:
                git(path, "fetch", "--quiet", "--no-tags", expected_remote, latest)
                if not is_ancestor(path, current, latest):
                    ahead, behind = map(int, git(path, "rev-list", "--left-right", "--count",
                                                 f"{current}...{latest}").split())
                    blocked_reason = (f"Local development branch {branch}: {ahead} local and "
                                      f"{behind} upstream-only commits. Automatic updates are paused "
                                      "to preserve your local work.")
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as exc:
            error = f"remote check failed: {exc}"
    return {
        "current": current[:8], "latest": latest[:8],
        "available": latest != current and not error and not blocked_reason,
        "clean": clean, "changes": changes, "target": latest, "error": error,
        "blockedReason": blocked_reason, "branch": branch, "ahead": ahead, "behind": behind,
    }


def status(fetch: bool = True) -> dict:
    root = source_root()
    result = {"ok": False, "installed": root is not None, "sourceRoot": str(root or ""),
              "available": False, "installable": False, "projects": {},
              "blockedReason": "", "error": ""}
    if root is None:
        result["error"] = "Umbriel source checkouts were not found"
        return result
    try:
        for name, remote in PROJECTS:
            result["projects"][name] = project_status(root / name, remote, fetch)
        rows = list(result["projects"].values())
        result["available"] = any(row["available"] for row in rows)
        result["installable"] = all(row["clean"] and not row["error"]
                                    and not row.get("blockedReason") for row in rows)
        result["ok"] = not any(row["error"] for row in rows)
        errors = [f"{name}: {row['error']}" for name, row in result["projects"].items() if row["error"]]
        blocks = [f"{name}: {row['blockedReason']}" for name, row in result["projects"].items()
                  if row.get("blockedReason")]
        result["blockedReason"] = "; ".join(blocks)
        if errors:
            result["error"] = "; ".join(errors)
        if result["available"] and any(not row["clean"] for row in rows):
            dirty = []
            for name, row in result["projects"].items():
                if not row["clean"]:
                    paths = ", ".join(row.get("changes", [])) or "unknown files"
                    dirty.append(f"{name}: {paths}")
            result["blockedReason"] = "; ".join(filter(None, [result["blockedReason"],
                "Local source changes block this update: " + "; ".join(dirty)]))
    except (OSError, subprocess.SubprocessError) as exc:
        result["error"] = f"Umbriel check failed: {exc}"
    return result


def build_project(source: pathlib.Path, project_name: str) -> pathlib.Path:
    if project_name not in dict(PROJECTS):
        raise RuntimeError("Unknown compositor stack project")
    build = source / "build-nbshell"
    setup = ["meson", "setup", str(build), str(source), "--buildtype=release", f"--prefix={PREFIX}"]
    if build.is_dir():
        setup.append("--reconfigure")
    subprocess.run(setup, check=True)
    options = json.loads(subprocess.check_output(
        ["meson", "introspect", str(build), "--buildoptions"], text=True,
    ))
    project = json.loads(subprocess.check_output(
        ["meson", "introspect", str(build), "--projectinfo"], text=True,
    ))
    compositor = project_name == "umbriel"
    test_option = next((option for option in options if option.get("name") == "tests"), None)
    if compositor and test_option:
        value = "true" if test_option.get("type") == "boolean" else "enabled"
        subprocess.run(["meson", "configure", str(build), "-Dtests=" + value], check=True)
    subprocess.run(["meson", "compile", "-C", str(build)], check=True)
    tests = json.loads(subprocess.check_output(
        ["meson", "introspect", str(build), "--tests"], text=True,
    ))
    if compositor and not tests:
        raise RuntimeError("Umbriel defines no tests; refusing an untested compositor install")
    if not tests:
        print(f"{project.get('descriptive_name', source.name)} defines no upstream tests.")
    subprocess.run(["meson", "test", "-C", str(build), "--print-errorlogs"], check=True)
    if compositor:
        # Check required commands/actions without pretending every newer commit
        # has the exact provenance of the pinned reference fixture.
        import importlib.util
        spec = importlib.util.spec_from_file_location("umbriel_contract", pathlib.Path(__file__).with_name("umbriel-contract.py"))
        contract = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(contract)
        try:
            discovered = contract.discover(str(build / "umbriel"), contract.load_contract())
        except contract.ContractError as exc:
            raise RuntimeError(str(exc)) from exc
        missing = [row["id"] for row in discovered["capabilities"] if row["required"] and not row["available"]]
        if missing:
            raise RuntimeError("Umbriel is missing required capabilities: " + ", ".join(missing))
    return build


def prepare_worktree(path: pathlib.Path, expected_remote: str, target: str,
                     destination: pathlib.Path) -> None:
    if REVISION_RE.fullmatch(target) is None:
        raise RuntimeError("refusing to fetch an invalid target revision")
    remote = git(path, "remote", "get-url", "origin")
    if canonical_remote(remote) != canonical_remote(expected_remote):
        raise RuntimeError(f"unexpected origin: {remote}")
    if git(path, "status", "--porcelain"):
        raise RuntimeError("source checkout has local changes")
    current = git(path, "rev-parse", "HEAD")
    git(path, "fetch", "--quiet", "--no-tags", expected_remote, target)
    if not is_ancestor(path, current, target):
        raise RuntimeError("target revision does not fast-forward the current checkout")
    git(path, "worktree", "add", "--quiet", "--detach", str(destination), target)
    git(destination, "submodule", "update", "--init", "--recursive")


def advance_checkout(path: pathlib.Path, expected_remote: str, target: str) -> None:
    remote = git(path, "remote", "get-url", "origin")
    if canonical_remote(remote) != canonical_remote(expected_remote):
        raise RuntimeError(f"unexpected origin after installation: {remote}")
    if git(path, "status", "--porcelain"):
        raise RuntimeError("source checkout changed during installation")
    git(path, "checkout", "--quiet", "--detach", target)


def install(assume_yes: bool) -> int:
    info = status(fetch=True)
    if not info["ok"] or not info["installable"]:
        print(info["error"] or info["blockedReason"] or "Local source changes block this update.",
              file=sys.stderr)
        return 1
    if not info["available"]:
        print("Umbriel and its portal are already up to date.")
        return 0
    print("Umbriel compositor stack updates are available:")
    for name, row in info["projects"].items():
        print(f"  {name}: {row['current']} → {row['latest']}")
    if not assume_yes and input("Build, test, and install both projects? [y/N] ").strip().lower() not in {"y", "yes"}:
        print("Update cancelled.")
        return 125

    root = pathlib.Path(info["sourceRoot"])
    with tempfile.TemporaryDirectory(prefix="nbshell-umbriel-update-") as temp_name:
        temp = pathlib.Path(temp_name)
        worktrees = []
        installed = []
        builds = []
        try:
            for name, remote in PROJECTS:
                source = root / name
                worktree = temp / name
                target = info["projects"][name]["target"]
                worktrees.append((source, worktree))
                prepare_worktree(source, remote, target, worktree)
                builds.append(build_project(worktree, name))
                installed.append((source, remote, target))
            stage = temp / "install-stage"
            for build in builds:
                subprocess.run(
                    ["meson", "install", "-C", str(build), "--destdir", str(stage)],
                    check=True,
                )
            command = [sys.executable, str(INSTALL_TREE), str(stage), str(PREFIX)]
            if PREFIX == pathlib.Path("/usr/local"):
                command.insert(0, "sudo")
            subprocess.run(command, check=True)
            for source, remote, target in installed:
                advance_checkout(source, remote, target)
        finally:
            for source, worktree in reversed(worktrees):
                git(source, "worktree", "remove", "--force", str(worktree), check=False)
                git(source, "worktree", "prune", check=False)

    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    print("Umbriel stack installed. Log out and back in to start the new compositor build.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Check and update the Umbriel compositor stack")
    parser.add_argument("command", nargs="?", choices=("check", "install", "build"), default="check")
    parser.add_argument("--project", choices=tuple(dict(PROJECTS)), help=argparse.SUPPRESS)
    parser.add_argument("--source", type=pathlib.Path, help=argparse.SUPPRESS)
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--offline", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--coordinated", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.command == "build" and (args.source is None or args.project is None):
        parser.error("build requires --source and --project")
    if args.command == "check":
        print(json.dumps(status(fetch=not args.offline)))
        return 0
    try:
        if args.command == "build":
            build_project(args.source.resolve(), args.project)
            return 0
        if not args.coordinated:
            command = [sys.executable, str(pathlib.Path(__file__).with_name("update-coordinator.py")), "compositor"]
            if args.yes:
                command.append("--yes")
            return subprocess.call(command)
        import runpy
        guard = runpy.run_path(str(pathlib.Path(__file__).with_name("update-coordinator.py")))
        if not guard["inherited_guard"]():
            raise ValueError("The internal updater requires an active update coordinator")
        return install(args.yes)
    except EOFError:
        print("Confirmation requires a terminal; rerun interactively or pass --yes.", file=sys.stderr)
        return 125
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as exc:
        print(f"Umbriel update failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
