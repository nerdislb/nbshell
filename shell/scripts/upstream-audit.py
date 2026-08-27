#!/usr/bin/env python3
"""Read-only revision check for external nbshell sources."""

import argparse
import json
import os
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse


def github_head(repository: str) -> str:
    """Return GitHub's default-branch head without cloning a large repository."""
    parsed = urlparse(repository)
    if parsed.hostname != "github.com":
        return ""
    parts = parsed.path.strip("/").removesuffix(".git").split("/")
    if len(parts) != 2:
        return ""
    request = urllib.request.Request(
        f"https://api.github.com/repos/{parts[0]}/{parts[1]}/commits/HEAD",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "nbshell-upstream-audit"},
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.load(response)
        return str(data.get("sha", ""))
    except (OSError, ValueError, urllib.error.HTTPError):
        return ""


def remote_head(repository: str, api_first: bool = False) -> str:
    if api_first:
        remote = github_head(repository)
        if remote:
            return remote
    try:
        result = subprocess.run(
            ["git", "ls-remote", repository, "HEAD"],
            capture_output=True, text=True, timeout=20, check=False,
        )
    except subprocess.TimeoutExpired:
        result = None
    if result and not result.returncode and result.stdout.strip():
        return result.stdout.split()[0]
    return github_head(repository)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--notify", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    catalog = json.loads((root / "Catalog" / "external-sources.json").read_text())
    pending = []
    failed = []
    for source in catalog["sources"]:
        remote = remote_head(source["repository"], source.get("check") == "github-api")
        if not remote:
            failed.append(source["name"])
            continue
        reviewed = source["reviewedCommit"]
        marker = "current" if remote.startswith(reviewed) else "review available"
        print(f"{source['name']}: {marker} ({reviewed} -> {remote[:7]})")
        if marker != "current":
            pending.append(source["name"])
    if args.notify and pending and os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        subprocess.run([
            "notify-send", "nbshell source review",
            f"{len(pending)} external source(s) changed: " + ", ".join(pending),
        ], check=False)
    if failed:
        print("Unavailable: " + ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
