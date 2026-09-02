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
    clean = git(path, "status", "--porcelain") == ""
    latest = current
    error = ""
    if fetch:
        try:
            latest = remote_head(expected_remote)
            if latest != current:
                git(path, "fetch", "--quiet", "--no-tags", expected_remote, latest)
                if not is_ancestor(path, current, latest):
                    error = "remote HEAD does not fast-forward the current checkout"
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            error = f"remote check failed: {exc}"
    return {
        "current": current[:8], "latest": latest[:8],
        "available": latest != current and not error,
        "clean": clean, "target": latest, "error": error,
    }


def status(fetch: bool = True) -> dict:
    root = source_root()
    result = {"ok": False, "installed": root is not None, "sourceRoot": str(root or ""),
              "available": False, "installable": False, "projects": {}, "error": ""}
    if root is None:
        result["error"] = "Umbriel source checkouts were not found"
        return result
    try:
        for name, remote in PROJECTS:
            result["projects"][name] = project_status(root / name, remote, fetch)
        rows = list(result["projects"].values())
        result["available"] = any(row["available"] for row in rows)
        result["installable"] = all(row["clean"] and not row["error"] for row in rows)
        result["ok"] = not any(row["error"] for row in rows)
        errors = [f"{name}: {row['error']}" for name, row in result["projects"].items() if row["error"]]
        if errors:
            result["error"] = "; ".join(errors)
        elif not result["installable"]:
            result["error"] = "A source checkout has local changes; update is blocked"
    except (OSError, subprocess.SubprocessError) as exc:
        result["error"] = f"Umbriel check failed: {exc}"
    return result


def build_project(source: pathlib.Path) -> pathlib.Path:
    build = source / "build-nbshell"
    setup = ["meson", "setup", str(build), str(source), "--buildtype=release", f"--prefix={PREFIX}"]
    if build.is_dir():
        setup.append("--reconfigure")
    subprocess.run(setup, check=True)
    subprocess.run(["meson", "compile", "-C", str(build)], check=True)
    subprocess.run(["meson", "test", "-C", str(build), "--print-errorlogs"], check=True)
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
        print(info["error"], file=sys.stderr)
        return 1
    if not info["available"]:
        print("Umbriel and its portal are already up to date.")
        return 0
    print("Umbriel compositor stack updates are available:")
    for name, row in info["projects"].items():
        print(f"  {name}: {row['current']} → {row['latest']}")
    if not assume_yes and input("Build, test, and install both projects? [y/N] ").strip().lower() not in {"y", "yes"}:
        print("Update cancelled.")
        return 0

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
                builds.append(build_project(worktree))
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
    parser.add_argument("command", nargs="?", choices=("check", "install"), default="check")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--offline", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.command == "check":
        print(json.dumps(status(fetch=not args.offline)))
        return 0
    try:
        return install(args.yes)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"Umbriel update failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
