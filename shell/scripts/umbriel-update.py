#!/usr/bin/env python3
"""Check and update the user-local Umbriel compositor stack."""

from __future__ import annotations

import argparse
import json
import os
import pathlib

import subprocess
import sys

PROJECTS = (
    ("umbriel", "https://github.com/noctalia-dev/umbriel.git",
     "e677dbbe2728ee65156bdbcc6775b0b36b388b64"),
    ("xdg-desktop-portal-umbriel", "https://github.com/noctalia-dev/xdg-desktop-portal-umbriel.git",
     "d996f0c2bd4e8c868c0a143f0c9ce060f3c47ed5"),
)
PREFIX = pathlib.Path(os.environ.get("NBSHELL_UMBRIEL_PREFIX", "/usr/local"))


def source_root() -> pathlib.Path | None:
    configured = os.environ.get("NBSHELL_UMBRIEL_SOURCE_DIR")
    candidates = ([pathlib.Path(configured).expanduser()] if configured else []) + [
        pathlib.Path.home() / "projects",
        pathlib.Path.home() / ".cache/nbshell/umbriel-sources",
    ]
    for candidate in candidates:
        if all((candidate / name / ".git").exists() for name, _, _ in PROJECTS):
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


def project_status(path: pathlib.Path, expected_remote: str, revision: str, fetch: bool = True) -> dict:
    current = git(path, "rev-parse", "HEAD")
    remote = git(path, "remote", "get-url", "origin")
    expected = canonical_remote(expected_remote)
    if canonical_remote(remote) != expected:
        return {"current": current[:8], "latest": "", "available": False, "clean": False,
                "error": f"unexpected origin: {remote}"}
    clean = git(path, "status", "--porcelain") == ""
    latest = revision
    error = ""
    if fetch:
        try:
            subprocess.run(
                ["git", "ls-remote", expected_remote, "HEAD"], text=True,
                capture_output=True, check=True, timeout=20,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            error = f"remote check failed: {exc}"
    return {
        "current": current[:8], "latest": latest[:8], "available": latest != current,
        "clean": clean, "error": error,
    }


def status(fetch: bool = True) -> dict:
    root = source_root()
    result = {"ok": False, "installed": root is not None, "sourceRoot": str(root or ""),
              "available": False, "installable": False, "projects": {}, "error": ""}
    if root is None:
        result["error"] = "Umbriel source checkouts were not found"
        return result
    try:
        for name, remote, revision in PROJECTS:
            result["projects"][name] = project_status(root / name, remote, revision, fetch)
        rows = list(result["projects"].values())
        result["available"] = any(row["available"] for row in rows)
        result["installable"] = all(row["clean"] and not row["error"] for row in rows)
        result["ok"] = not any(row["error"] for row in rows)
        if not result["installable"] and not result["error"]:
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
    builds = []
    for name, _, revision in PROJECTS:
        path = root / name
        git(path, "fetch", "--prune", "origin")
        git(path, "checkout", "--detach", revision)
        git(path, "submodule", "update", "--init", "--recursive")
        builds.append(build_project(path))
    for build in builds:
        command = ["meson", "install", "-C", str(build)]
        if PREFIX == pathlib.Path("/usr/local"):
            command.insert(0, "sudo")
        subprocess.run(command, check=True)

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
