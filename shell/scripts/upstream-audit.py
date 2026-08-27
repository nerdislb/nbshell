#!/usr/bin/env python3
"""Read-only revision check for external nbshell sources."""

import argparse
import json
import os
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--notify", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    catalog = json.loads((root / "Catalog" / "external-sources.json").read_text())
    pending = []
    failed = []
    for source in catalog["sources"]:
        result = subprocess.run(
            ["git", "ls-remote", source["repository"], "HEAD"],
            capture_output=True, text=True, timeout=20, check=False,
        )
        if result.returncode or not result.stdout.strip():
            failed.append(source["name"])
            continue
        remote = result.stdout.split()[0]
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
