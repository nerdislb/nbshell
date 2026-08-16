#!/usr/bin/env python3
"""On-demand status collection for nbshell's system hub."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def run(*args, timeout=5):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def unit(name, user=True):
    args = ["systemctl"] + (["--user"] if user else []) + ["is-active", name]
    code, out, _ = run(*args)
    return code == 0 and out == "active"


def item(ident, label, detail, state="ok", command=""):
    return {"id": ident, "label": label, "detail": detail, "state": state, "command": command}


def count_lines(text):
    return len([line for line in text.splitlines() if line.strip()])


def executable(name):
    """Resolve user tools even when systemd's manager PATH omits ~/.local/bin."""
    found = shutil.which(name)
    if found:
        return found
    local = Path.home() / ".local" / "bin" / name
    return str(local) if local.is_file() and os.access(local, os.X_OK) else ""


def collect():
    groups = []

    agents = []
    herdr = executable("herdr")
    if herdr:
        code, out, err = run(herdr, "agent", "list", "--json")
        if code != 0:
            code, out, err = run(herdr, "agent", "list")
        agents.append(item("herdr", "Herdr", f"{count_lines(out)} Eintraege" if code == 0 else (err or "nicht erreichbar"), "ok" if code == 0 else "warn", f"{herdr} agent list"))
    else:
        agents.append(item("herdr", "Herdr", "nicht installiert", "off"))
    hook_tool = Path(__file__).with_name("codex-hooks.py")
    hook_script = Path(__file__).with_name("codex-notify.sh")
    code, out, _ = run("python3", str(hook_tool), "status")
    agents.append(item("codex", "Codex Notifications", "Hooks aktiv" if out == "installed" else "Hooks nicht aktiv", "ok" if out == "installed" else "warn", f"python3 {hook_tool} install {hook_script}" if out != "installed" else ""))
    groups.append({"title": "AGENTEN", "items": agents})

    sync = []
    syncthing = unit("syncthing.service")
    sync.append(item("syncthing", "Syncthing", "Dienst aktiv" if syncthing else "Dienst nicht aktiv", "ok" if syncthing else "warn", "xdg-open http://127.0.0.1:8384"))
    if shutil.which("gh"):
        code, out, err = run("gh", "api", "notifications", "--jq", "length", timeout=10)
        sync.append(item("github", "GitHub Inbox", f"{out} ungelesen" if code == 0 else (err or "Anmeldung pruefen"), "ok" if code == 0 else "warn", "xdg-open https://github.com/notifications"))
    else:
        sync.append(item("github", "GitHub Inbox", "gh nicht installiert", "off"))
    groups.append({"title": "SYNC & INBOX", "items": sync})

    system = []
    if shutil.which("checkupdates"):
        code, out, _ = run("checkupdates", timeout=20)
        updates = count_lines(out)
        system.append(item("updates", "Arch Updates", f"{updates} Pakete" if code in (0, 2) else "Pruefung fehlgeschlagen", "warn" if updates else "ok", "nbshell update list"))
    pacnew = []
    for base in (Path("/etc"),):
        try:
            pacnew.extend(base.rglob("*.pacnew")); pacnew.extend(base.rglob("*.pacsave"))
        except OSError:
            pass
    system.append(item("pacnew", "Pacman Sentry", f"{len(pacnew)} pacnew/pacsave", "warn" if pacnew else "ok", "find /etc -type f \\( -name '*.pacnew' -o -name '*.pacsave' \\) -print"))
    cups = unit("cups.service", user=False)
    code, out, _ = run("lpstat", "-o") if shutil.which("lpstat") else (127, "", "")
    system.append(item("cups", "Drucker", (f"{count_lines(out)} Auftraege" if cups else "CUPS nicht aktiv"), "ok" if cups and not out else "warn", "xdg-open http://localhost:631"))
    groups.append({"title": "SYSTEM", "items": system})

    dev = []
    code, out, _ = run("ss", "-H", "-tlnp")
    dev.append(item("ports", "Portboard", f"{count_lines(out)} offene TCP-Listener", "ok" if code == 0 else "warn", "ss -tlnp"))
    dev.append(item("equalizer", "Equalizer", "EasyEffects bereit" if shutil.which("easyeffects") else "EasyEffects nicht installiert", "ok" if shutil.which("easyeffects") else "off", "easyeffects" if shutil.which("easyeffects") else ""))
    groups.append({"title": "ENTWICKLUNG & AUDIO", "items": dev})

    hardware = []
    if shutil.which("ddcutil"):
        code, out, err = run("ddcutil", "detect", "--brief", timeout=8)
        detected = code == 0 and "Display" in out
        detail = "DDC-Monitor erkannt" if detected else ((err or out).splitlines()[0] if (err or out) else "kein DDC-Monitor")
        hardware.append(item("ddc", "Externe Helligkeit", detail, "ok" if detected else "warn", "ddcutil detect"))
    else:
        hardware.append(item("ddc", "Externe Helligkeit", "ddcutil nicht installiert / nur eDP-1", "off"))
    decoder = shutil.which("zbarimg") or shutil.which("zxing")
    hardware.append(item("qr", "QR aus Screenshot", "Decoder bereit" if decoder else "zbarimg/ZXing nicht installiert", "ok" if decoder else "off"))
    groups.append({"title": "HARDWARE", "items": hardware})

    return {"groups": groups}


if __name__ == "__main__":
    if len(sys.argv) == 1 or sys.argv[1] == "status":
        print(json.dumps(collect(), ensure_ascii=False))
    else:
        raise SystemExit("Aufruf: system-hub.py status")
