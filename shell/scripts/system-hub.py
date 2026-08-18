#!/usr/bin/env python3
"""On-demand status collection for nbshell's system hub."""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


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


def item(ident, label, detail, state="ok", command="", details=None):
    return {"id": ident, "label": label, "detail": detail, "state": state,
            "command": command, "details": details or []}


def count_lines(text):
    return len([line for line in text.splitlines() if line.strip()])


def executable(name):
    """Resolve user tools even when systemd's manager PATH omits ~/.local/bin."""
    found = shutil.which(name)
    if found:
        return found
    local = Path.home() / ".local" / "bin" / name
    return str(local) if local.is_file() and os.access(local, os.X_OK) else ""


def syncthing_details():
    config = Path.home() / ".local/state/syncthing/config.xml"
    try:
        key = ET.parse(config).findtext("./gui/apikey") or ""
        request = urllib.request.Request("http://127.0.0.1:8384/rest/config/folders",
                                         headers={"X-API-Key": key})
        with urllib.request.urlopen(request, timeout=3) as response:
            folders = json.load(response)
        out = []
        for folder in folders[:20]:
            ident = str(folder.get("id", ""))
            label = str(folder.get("label") or ident)
            url = "http://127.0.0.1:8384/rest/db/status?folder=" + urllib.parse.quote(ident)
            req = urllib.request.Request(url, headers={"X-API-Key": key})
            with urllib.request.urlopen(req, timeout=3) as response:
                state = json.load(response)
            errors = int(state.get("errors", 0) or 0)
            need = int(state.get("needTotalItems", 0) or 0)
            out.append({"label": label, "detail": f"{need} open · {errors} errors",
                        "state": "warn" if errors or need else "ok"})
        return out
    except Exception as exc:
        return [{"label": "API", "detail": str(exc)[:160], "state": "warn"}]


def arch_news():
    try:
        request = urllib.request.Request("https://archlinux.org/feeds/news/",
                                         headers={"User-Agent": "nbshell-system-hub/1"})
        with urllib.request.urlopen(request, timeout=5) as response:
            root = ET.fromstring(response.read())
        rows = []
        for entry in root.findall("./channel/item")[:5]:
            title = entry.findtext("title") or "Arch News"
            date = (entry.findtext("pubDate") or "").split(" +")[0]
            link = entry.findtext("link") or "https://archlinux.org/news/"
            rows.append({"label": title, "detail": date, "state": "warn",
                         "command": "detached:xdg-open " + link})
        return rows
    except Exception as exc:
        return [{"label": "News", "detail": str(exc)[:140], "state": "warn"}]


def collect():
    groups = []

    agents = []
    herdr = executable("herdr")
    if herdr:
        code, out, err = run(herdr, "agent", "list", "--json")
        if code != 0:
            code, out, err = run(herdr, "agent", "list")
        try:
            agent_data = json.loads(out).get("result", {}).get("agents", []) if code == 0 else []
        except ValueError:
            agent_data = []
        agent_rows = [{
            "label": str(a.get("agent", "Agent")).capitalize(),
            "detail": str(a.get("agent_status", "?")) + " · " + str(a.get("terminal_title_stripped") or a.get("cwd", "")),
            "state": "warn" if a.get("agent_status") in ("waiting", "permission") else "ok",
            "command": "detached:python3 " + str(Path(__file__).resolve()) + " herdr-focus " + str(a.get("pane_id", ""))
        } for a in agent_data]
        agents.append(item("herdr", "Herdr", f"{len(agent_data)} Agenten" if code == 0 else (err or "unreachable"), "ok" if code == 0 else "warn", f"{herdr} agent list", agent_rows))
    else:
        agents.append(item("herdr", "Herdr", "not installed", "off"))
    hook_tool = Path(__file__).with_name("codex-hooks.py")
    hook_script = Path(__file__).with_name("codex-notify.sh")
    code, out, _ = run("python3", str(hook_tool), "status")
    agents.append(item("codex", "Codex Notifications", "Hooks aktiv" if out == "installed" else "Hooks inactive", "ok" if out == "installed" else "warn", f"python3 {hook_tool} install {hook_script}" if out != "installed" else ""))
    groups.append({"title": "AGENTEN", "items": agents})

    sync = []
    syncthing = unit("syncthing.service")
    sync.append(item("syncthing", "Syncthing", "Dienst aktiv" if syncthing else "Service inactive", "ok" if syncthing else "warn", "xdg-open http://127.0.0.1:8384", syncthing_details() if syncthing else []))
    if shutil.which("gh"):
        code, out, err = run("gh", "api", "notifications", timeout=10)
        try:
            notices = json.loads(out) if code == 0 else []
        except ValueError:
            notices = []
        rows = [{"label": str(n.get("repository", {}).get("full_name", "GitHub")),
                 "detail": str(n.get("subject", {}).get("title", "")), "state": "warn"}
                for n in notices[:15]]
        sync.append(item("github", "GitHub Inbox", f"{len(notices)} ungelesen" if code == 0 else (err or "Check login"), "ok" if code == 0 and not notices else "warn", "xdg-open https://github.com/notifications", rows))
    else:
        sync.append(item("github", "GitHub Inbox", "gh not installed", "off"))
    groups.append({"title": "SYNC & INBOX", "items": sync})

    system = []
    news = arch_news()
    system.append(item("arch-news", "Arch News", f"{len(news)} aktuelle Hinweise", "warn" if news else "ok", "xdg-open https://archlinux.org/news/", news))
    if shutil.which("checkupdates"):
        code, out, _ = run("checkupdates", timeout=20)
        updates = count_lines(out)
        rows = [{"label": line.split()[0], "detail": " ".join(line.split()[1:]), "state": "warn"}
                for line in out.splitlines() if line.strip()][:20]
        system.append(item("updates", "Arch Updates", f"{updates} Pakete" if code in (0, 2) else "Check failed", "warn" if updates else "ok", "nbshell update list", rows))
    pacnew = []
    for base in (Path("/etc"),):
        try:
            pacnew.extend(base.rglob("*.pacnew")); pacnew.extend(base.rglob("*.pacsave"))
        except OSError:
            pass
    pac_rows = [{"label": path.name, "detail": str(path.parent), "state": "warn"} for path in pacnew[:20]]
    system.append(item("pacnew", "Pacman Sentry", f"{len(pacnew)} pacnew/pacsave", "warn" if pacnew else "ok", "find /etc -type f \\( -name '*.pacnew' -o -name '*.pacsave' \\) -print", pac_rows))
    cups = unit("cups.service", user=False)
    code, out, _ = run("lpstat", "-o") if shutil.which("lpstat") else (127, "", "")
    _, printers, _ = run("lpstat", "-p") if shutil.which("lpstat") else (127, "", "")
    print_rows = [{"label": line.split()[1] if len(line.split()) > 1 else "Drucker",
                   "detail": " ".join(line.split()[2:]), "state": "ok" if "idle" in line else "warn"}
                  for line in printers.splitlines() if line.strip()]
    print_rows += [{"label": line.split()[0], "detail": "Druckauftrag", "state": "warn"}
                   for line in out.splitlines() if line.strip()]
    system.append(item("cups", "Drucker", (f"{count_lines(out)} Auftraege" if cups else "CUPS inactive"), "ok" if cups and not out else "warn", "xdg-open http://localhost:631", print_rows))
    groups.append({"title": "SYSTEM", "items": system})

    dev = []
    code, out, _ = run("ss", "-H", "-tlnp")
    port_rows = []
    for line in out.splitlines()[:30]:
        fields = line.split()
        endpoint = fields[3] if len(fields) > 3 else "?"
        process = re.search(r'\(\("([^\"]+)",pid=(\d+)', line)
        detail = (process.group(1) + " · PID " + process.group(2)) if process else "System/anderer Benutzer"
        port_rows.append({"label": endpoint, "detail": detail, "state": "ok"})
    dev.append(item("ports", "Portboard", f"{count_lines(out)} offene TCP-Listener", "ok" if code == 0 else "warn", "ss -tlnp", port_rows))
    dev.append(item("equalizer", "Equalizer", "EasyEffects ready" if shutil.which("easyeffects") else "EasyEffects not installed", "ok" if shutil.which("easyeffects") else "off", "easyeffects" if shutil.which("easyeffects") else ""))
    groups.append({"title": "ENTWICKLUNG & AUDIO", "items": dev})

    hardware = []
    if shutil.which("ddcutil"):
        code, out, err = run("ddcutil", "detect", "--brief", timeout=8)
        detected = code == 0 and "Display" in out
        detail = "DDC-Monitor erkannt" if detected else ((err or out).splitlines()[0] if (err or out) else "no DDC monitor")
        hardware.append(item("ddc", "External brightness", detail, "ok" if detected else "warn", "ddcutil detect"))
    else:
        hardware.append(item("ddc", "External brightness", "ddcutil not installed / nur eDP-1", "off"))
    decoder = shutil.which("zbarimg") or shutil.which("zxing")
    hardware.append(item("qr", "QR aus Screenshot", "Decoder ready" if decoder else "zbarimg/ZXing not installed", "ok" if decoder else "off"))
    groups.append({"title": "HARDWARE", "items": hardware})

    return {"groups": groups}


if __name__ == "__main__":
    if len(sys.argv) == 1 or sys.argv[1] == "status":
        print(json.dumps(collect(), ensure_ascii=False))
    elif sys.argv[1] == "herdr-focus" and len(sys.argv) == 3:
        herdr = executable("herdr")
        if not herdr:
            raise SystemExit("Herdr fehlt")
        run(herdr, "agent", "focus", sys.argv[2])
        code, windows, _ = run("niri", "msg", "-j", "windows")
        try:
            candidates = json.loads(windows) if code == 0 else []
        except ValueError:
            candidates = []
        target = next((w for w in candidates if str(w.get("title", "")).lower() == "herdr"), None)
        if target:
            run("niri", "msg", "action", "focus-window", "--id", str(target.get("id")))
    else:
        raise SystemExit("Aufruf: system-hub.py status|herdr-focus PANE")
