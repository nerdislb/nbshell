#!/usr/bin/env python3
"""Merge/remove nbshell-owned Codex lifecycle hooks atomically."""

import json
import os
from pathlib import Path
import sys
import tempfile

OWNER = "--owner=nbshell.codex-notifications"
EVENTS = ("PermissionRequest", "Stop")


def owned(hook):
    return isinstance(hook, dict) and OWNER in str(hook.get("command", ""))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".hooks.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush(); os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    script = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    path = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "hooks.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except (OSError, ValueError) as exc:
        raise SystemExit(f"{path} is unreadable and was not changed: {exc}")
    if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
        raise SystemExit(f"{path} does not contain a supported hook format")
    hooks = data.setdefault("hooks", {})
    present = any(owned(h) for groups in hooks.values() if isinstance(groups, list)
                  for group in groups if isinstance(group, dict)
                  for h in group.get("hooks", []) if isinstance(group.get("hooks", []), list))
    if action == "status":
        print("installed" if present else "not-installed")
        return
    for event in list(hooks):
        groups = hooks[event]
        if not isinstance(groups, list): continue
        cleaned = []
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                cleaned.append(group); continue
            remaining = [hook for hook in group["hooks"] if not owned(hook)]
            if remaining:
                cleaned.append({**group, "hooks": remaining})
        if cleaned: hooks[event] = cleaned
        else: hooks.pop(event, None)
    if action == "install":
        if script is None or not script.is_file(): raise SystemExit("Hook-Skript fehlt")
        for event in EVENTS:
            hooks.setdefault(event, []).append({"hooks": [{
                "type": "command",
                "command": f"{script} {OWNER} --event={event}",
                "timeout": 3
            }]})
    elif action != "uninstall":
        raise SystemExit("Aufruf: codex-hooks.py status|install SCRIPT|uninstall")
    write(path, data)
    print("installed" if action == "install" else "removed")


if __name__ == "__main__": main()
