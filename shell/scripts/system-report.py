#!/usr/bin/env python3
"""Generate an agent-safe nbshell system map without persistent indexing."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess


HOME = Path.home()
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
RUNTIME = CONFIG_HOME / "quickshell/nbshell"


def run(command: list[str], timeout: float = 3.0) -> str:
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, check=False
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def json_run(command: list[str]) -> object:
    try:
        return json.loads(run(command) or "null")
    except ValueError:
        return None


def unit_state(name: str) -> str:
    value = run(["systemctl", "--user", "is-active", name])
    return value or "unavailable"


def backend() -> str:
    if os.environ.get("UMBRIEL_SOCKET") or os.environ.get("XDG_CURRENT_DESKTOP", "").lower() == "umbriel":
        return "umbriel"
    if os.environ.get("NIRI_SOCKET"):
        return "niri"
    return "unknown"


def collect() -> dict:
    active_backend = backend()
    outputs = json_run(["umbriel", "outputs", "--json"]) if active_backend == "umbriel" else None
    if active_backend == "niri":
        outputs = json_run(["niri", "msg", "--json", "outputs"])

    plugin_script = RUNTIME / "scripts/plugins.sh"
    plugins = json_run(["bash", str(plugin_script), "list"]) if plugin_script.is_file() else []
    config = json_run(["jq", "{theme,mode,edge,enabledPlugins}", str(CONFIG_HOME / "nbshell/config.json")]) or {}
    failed = run(["systemctl", "--user", "--failed", "--no-legend", "--plain"])

    return {
        "schemaVersion": 1,
        "system": {
            "hostname": platform.node(),
            "kernel": platform.release(),
            "architecture": platform.machine(),
            "distribution": run(["sh", "-c", ". /etc/os-release && printf '%s' \"$PRETTY_NAME\""]),
        },
        "desktop": {
            "backend": active_backend,
            "umbrielVersion": run(["umbriel", "--version"]),
            "niriVersion": run(["niri", "--version"]),
            "nbshellVersion": (RUNTIME / "VERSION").read_text().strip() if (RUNTIME / "VERSION").is_file() else "unknown",
            "theme": config.get("theme", "unknown"),
            "barMode": config.get("mode", "unknown"),
            "barEdge": config.get("edge", "unknown"),
            "outputs": outputs or [],
        },
        "services": {
            "nbshell": unit_state("nbshell.service"),
            "resumeGuard": unit_state("nbshell-umbriel-resume-guard.service"),
            "portal": unit_state("xdg-desktop-portal.service"),
            "umbrielPortal": unit_state("xdg-desktop-portal-umbriel.service"),
            "failed": failed.splitlines() if failed else [],
        },
        "extensions": {
            "enabled": config.get("enabledPlugins", []),
            "installed": [
                {key: item.get(key, "") for key in ("id", "name", "version", "kinds")}
                for item in plugins if isinstance(item, dict)
            ],
        },
        "paths": {
            "config": str(CONFIG_HOME / "nbshell"),
            "runtime": str(RUNTIME),
            "umbriel": str(CONFIG_HOME / "umbriel/config.toml"),
            "niriFallback": str(CONFIG_HOME / "niri/config.kdl"),
        },
        "tools": {
            name: bool(shutil.which(name))
            for name in ("qs", "umbriel", "niri", "grim", "slurp", "wf-recorder", "ffmpeg", "fd")
        },
    }


def markdown(data: dict) -> str:
    system = data["system"]
    desktop = data["desktop"]
    services = data["services"]
    extensions = data["extensions"]
    output_count = len(desktop["outputs"]) if isinstance(desktop["outputs"], (list, dict)) else 0
    rows = [
        "# nbshell system report",
        "",
        "> Generated locally. It intentionally excludes window titles, clipboard data, notifications, addresses, and credentials.",
        "",
        "## System",
        "",
        f"- Host: `{system['hostname']}`",
        f"- Distribution: {system['distribution'] or 'unknown'}",
        f"- Kernel: `{system['kernel']}` ({system['architecture']})",
        "",
        "## Desktop",
        "",
        f"- Backend: **{desktop['backend']}**",
        f"- nbshell: `{desktop['nbshellVersion']}`",
        f"- Umbriel: `{desktop['umbrielVersion'] or 'unavailable'}`",
        f"- Niri fallback: `{desktop['niriVersion'] or 'unavailable'}`",
        f"- Appearance: `{desktop['theme']}` / `{desktop['barMode']}` / `{desktop['barEdge']}`",
        f"- Detected outputs: {output_count}",
        "",
        "## User services",
        "",
    ]
    rows.extend(f"- {name}: `{state}`" for name, state in services.items() if name != "failed")
    rows += [
        f"- Failed user units: {len(services['failed'])}",
        "",
        "## Extensions",
        "",
        f"- Installed: {len(extensions['installed'])}",
        f"- Enabled: {', '.join(extensions['enabled']) or 'none'}",
        "",
        "## Stable entry points",
        "",
        "- `nbshell status`",
        "- `nbshell compositor status`",
        "- `nbshell agent doctor`",
        "- `nbshell update`",
        "- `nbshell log`",
        "",
    ]
    return "\n".join(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--write", nargs="?", const="", metavar="PATH", help="write Markdown to PATH or the default state path")
    args = parser.parse_args()
    data = collect()
    text = json.dumps(data, indent=2) + "\n" if args.json else markdown(data)
    if args.write is not None:
        target = Path(args.write).expanduser() if args.write else Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "nbshell/system-report.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(markdown(data), encoding="utf-8")
        print(target)
    else:
        print(text, end="" if text.endswith("\n") else "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
