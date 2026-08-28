#!/usr/bin/env python3
"""Deterministic contract checks for bin/nbshell CLI help, JSON catalog, and doc consistency."""

from __future__ import annotations

import glob
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
NBSHELL = ROOT / "bin/nbshell"

assert NBSHELL.is_file() and os.access(NBSHELL, os.X_OK), f"bin/nbshell is not executable: {NBSHELL}"

# 1. Test CLI help invocations
for arg in ("--help", "-h", "help", ""):
    result = subprocess.run([str(NBSHELL), *([arg] if arg else [])],
                            text=True, capture_output=True, check=False)
    assert result.returncode == 0, f"nbshell {arg} failed with code {result.returncode}"
    assert "nbshell -- an independent Quickshell desktop shell" in result.stdout
    assert "nbshell start [-d]" in result.stdout
    assert "nbshell restart" in result.stdout
    assert "nbshell agent hermes-mode [restricted|research|workspace|trusted]" in result.stdout
    assert "nbshell agent hermes-team" in result.stdout
    assert "nbshell agent hermes-brain" in result.stdout

# 2. Test version output
for arg in ("--version", "-V", "version"):
    result = subprocess.run([str(NBSHELL), arg], text=True, capture_output=True, check=False)
    assert result.returncode == 0
    assert re.match(r"^nbshell (?:development|[0-9]+\.[0-9]+\.[0-9]+.*)$", result.stdout.strip()), \
        f"unexpected version output: {result.stdout.strip()}"

# 3. Test machine-readable JSON catalog
catalog_result = subprocess.run([str(NBSHELL), "commands", "--json"],
                                text=True, capture_output=True, check=False)
assert catalog_result.returncode == 0, f"commands --json failed with code {catalog_result.returncode}"

catalog_data = json.loads(catalog_result.stdout)
assert catalog_data.get("schemaVersion") == 1, f"invalid schemaVersion: {catalog_data.get('schemaVersion')}"
commands = catalog_data.get("commands", [])
assert len(commands) >= 70, f"expected at least 70 commands in catalog, got {len(commands)}"

catalog_map = {}
for item in commands:
    cmd = item.get("command", "")
    summary = item.get("summary", "")
    assert cmd and isinstance(cmd, str), f"invalid command string: {cmd!r}"
    assert summary and isinstance(summary, str), f"empty or invalid summary for command {cmd!r}"
    assert cmd.startswith("nbshell "), f"command does not start with 'nbshell ': {cmd!r}"
    catalog_map[cmd] = summary

# Validate special summary override for commands --json
assert catalog_map.get("nbshell commands --json") == "Print this machine-readable CLI catalog", \
    f"unexpected catalog summary: {catalog_map.get('nbshell commands --json')}"

# 4. Validate critical subcommands in catalog
required_catalog_commands = (
    "nbshell start [-d]",
    "nbshell stop",
    "nbshell restart",
    "nbshell bar",
    "nbshell island",
    "nbshell pill",
    "nbshell theme",
    "nbshell theme install [--force] <url|directory>",
    "nbshell widget",
    "nbshell audio up|down",
    "nbshell audio status",
    "nbshell launcher",
    "nbshell notify",
    "nbshell display",
    "nbshell update",
    "nbshell ai",
    "nbshell agent list [--json]",
    "nbshell agent default [id]",
    "nbshell agent launch [id] [--project <path>]",
    "nbshell agent quick [--project <path>]",
    "nbshell agent hermes-provider [codex|claude|gemini]",
    "nbshell agent hermes-mode [restricted|research|workspace|trusted]",
    "nbshell agent hermes-broker [status|setup|test|remove]",
    "nbshell agent hermes-job <create|list|review|apply|install|push|reject>",
    "nbshell agent hermes-team <list|pause|resume|cancel|apply|install|push|reject>",
    "nbshell agent hermes-brain <list|apply|push|reject>",
    "nbshell agent doctor",
    "nbshell agent skills",
    "nbshell capture",
    "nbshell calculator",
    "nbshell store",
    "nbshell system-report",
    "nbshell memory-guard",
    "nbshell demo start|stop",
    "nbshell whatsapp setup",
    "nbshell aether setup",
    "nbshell grid toggle",
    "nbshell todo",
    "nbshell notes",
    "nbshell habits",
    "nbshell plugins",
    "nbshell power",
    "nbshell greeter install orbital|regreet",
    "nbshell pip status|apply|size|corner|focus|close",
    "nbshell browser-theme status|setup|apply|setup-zen-live|doctor-zen-live",
    "nbshell video-trimmer status|install|update|remove",
    "nbshell wallpaper on|off",
    "nbshell config",
    "nbshell state",
    "nbshell status",
    "nbshell switch on",
    "nbshell switch off",
    "nbshell switch status",
    "nbshell keys",
    "nbshell cursor [theme] [size]",
    "nbshell text [8..28]",
    "nbshell polkit [on]",
    "nbshell auth approve-next [system|sudo|polkit-1]",
)

for req in required_catalog_commands:
    assert req in catalog_map, f"missing required command from catalog: {req}"

# 5. Check consistency of README and documentation commands
nbshell_code = (ROOT / "bin/nbshell").read_text(encoding="utf-8")
top_branches = set()
for branch in re.findall(r'^\s{4}([a-zA-Z0-9_|*? -]+)\)', nbshell_code, re.MULTILINE):
    for cmd in branch.split("|"):
        c = cmd.strip()
        if c and not c.startswith(("$", "#", '"', "-")):
            top_branches.add(c)

for md_path in sorted(ROOT.glob("**/*.md")):
    if ".git" in md_path.parts or "audits" in md_path.parts:
        continue
    content = md_path.read_text(encoding="utf-8")
    for match in re.finditer(r'`(nbshell\s+[^`]+)`', content):
        cmd = match.group(1).split("#")[0].strip()
        tokens = cmd.split()
        if len(tokens) >= 2 and not tokens[1].startswith("-"):
            sub = tokens[1]
            if sub in ("is", "can", "generates", "takes", "makes", "runs", "integrates",
                       "uses", "groups", "keeps", "owns", "manifest", "YouTube", "deploys",
                       "plugins", "takes"):
                continue
            assert sub in top_branches or sub == "log", f"{md_path}: undocumented or invalid CLI command `{cmd}` (subcommand {sub!r})"

print(f"CLI consistency and catalog validation: OK ({len(catalog_map)} commands verified)")
