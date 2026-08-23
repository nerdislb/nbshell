#!/usr/bin/env python3
"""nbshell agent registry, launcher, local-model status, and Herdr bridge."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "nbshell"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell"
CONFIG_FILE = CONFIG_DIR / "agents.json"
OLLAMA_PID = STATE_DIR / "ollama.pid"
NATIVE_FILE = STATE_DIR / "agent-sessions.json"
TMUX_SOCKET = "nbshell-agents"
TMUX_SESSION = "nbshell-agents"

AGENTS = {
    "codex": {"name": "Codex", "binary": "codex", "kind": "cloud", "prompt": "positional", "glyph": "code", "install": "npm install -g @openai/codex"},
    "claude": {"name": "Claude Code", "binary": "claude", "kind": "cloud", "prompt": "positional", "glyph": "claude", "install": "npm install -g @anthropic-ai/claude-code"},
    "agy": {"name": "Antigravity", "binary": "agy", "kind": "cloud", "prompt": "positional", "glyph": "spark", "install": ""},
    "opencode": {"name": "OpenCode", "binary": "opencode", "kind": "hybrid", "prompt": "opencode", "glyph": "terminal", "install": "paru -S opencode"},
    "gemini": {"name": "Gemini CLI", "binary": "gemini", "kind": "cloud", "prompt": "gemini", "glyph": "spark", "install": "npm install -g @google/gemini-cli"},
    "copilot": {"name": "GitHub Copilot", "binary": "copilot", "kind": "cloud", "prompt": "copilot", "glyph": "code", "install": "npm install -g @github/copilot"},
    "pi": {"name": "Pi", "binary": "pi", "kind": "hybrid", "prompt": "positional", "glyph": "terminal", "install": "npm install -g @mariozechner/pi-coding-agent"},
}

DEFAULT_CONFIG = {
    "defaultAgent": "codex",
    "profile": "balanced",
    "modelProfile": "cloud",
    "lastProject": "",
    "projectsDir": str(Path.home() / "projects"),
    "terminal": "",
    "modelProfiles": {
        "local": {"agent": "opencode", "model": ""},
        "private": {"agent": "opencode", "model": ""},
        "cloud": {"agent": "", "model": ""},
        "fast": {"agent": "codex", "model": ""},
        "strong": {"agent": "claude", "model": ""},
    },
}


def load_config() -> dict:
    try:
        data = json.loads(CONFIG_FILE.read_text())
        return DEFAULT_CONFIG | data if isinstance(data, dict) else DEFAULT_CONFIG.copy()
    except (OSError, ValueError):
        return DEFAULT_CONFIG.copy()


def save_config(data: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(CONFIG_FILE)


def load_native_state() -> dict:
    try:
        data = json.loads(NATIVE_FILE.read_text())
        return data if isinstance(data, dict) else {"sessions": []}
    except (OSError, ValueError):
        return {"sessions": []}


def save_native_state(data: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = NATIVE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(NATIVE_FILE)


def tmux(*args: str, input_text: str | None = None, timeout: float = 5, check: bool = True) -> subprocess.CompletedProcess:
    if not shutil.which("tmux"):
        raise SystemExit("The native Agent Console backend needs tmux. Install it with: sudo pacman -S tmux")
    result = subprocess.run(
        ["tmux", "-L", TMUX_SOCKET, *args], input=input_text, text=True,
        capture_output=True, timeout=timeout, check=False,
    )
    if check and result.returncode:
        raise SystemExit(result.stderr.strip() or "tmux command failed")
    return result


def native_sessions() -> list[dict]:
    if not shutil.which("tmux"):
        return []
    live = tmux("list-windows", "-t", TMUX_SESSION, "-F", "#{window_name}\t#{window_id}", check=False)
    if live.returncode:
        return [{
            "id": "nbshell:" + str(item.get("name", "")), "name": str(item.get("agent", "agent")),
            "status": "stopped", "project": str(item.get("project", "")),
            "title": str(item.get("label", item.get("name", ""))), "focused": False,
            "workspace": TMUX_SESSION, "backend": "nbshell",
        } for item in load_native_state().get("sessions", []) if item.get("name")]
    windows = {line.split("\t", 1)[0]: line.split("\t", 1)[1] for line in live.stdout.splitlines() if "\t" in line}
    state = load_native_state()
    rows = []
    kept = []
    for item in state.get("sessions", []):
        name = str(item.get("name", ""))
        if name not in windows:
            kept.append(item)
            rows.append({
                "id": "nbshell:" + name, "name": str(item.get("agent", "agent")),
                "status": "stopped", "project": str(item.get("project", "")),
                "title": str(item.get("label", name)), "focused": False,
                "workspace": TMUX_SESSION, "backend": "nbshell",
            })
            continue
        output = tmux("capture-pane", "-p", "-S", "-120", "-t", f"{TMUX_SESSION}:{name}").stdout
        digest = __import__("hashlib").sha256(output.encode()).hexdigest()
        old_digest = str(item.get("outputHash", ""))
        stable = int(item.get("stableChecks", 0)) + 1 if digest == old_digest else 0
        status = str(item.get("status", "idle"))
        if status == "working" and stable >= 2:
            status = "done"
        if status == "done" and digest != old_digest:
            status = "working"
        item.update(outputHash=digest, stableChecks=stable, status=status, window=windows[name])
        kept.append(item)
        rows.append({
            "id": "nbshell:" + name,
            "name": str(item.get("agent", "agent")),
            "status": status,
            "project": str(item.get("project", "")),
            "title": str(item.get("label", name)),
            "focused": False,
            "workspace": TMUX_SESSION,
            "backend": "nbshell",
        })
    state["sessions"] = kept
    save_native_state(state)
    return rows


def native_target(target: str) -> str:
    if not target.startswith("nbshell:"):
        raise SystemExit("Not an nbshell-native session.")
    return target.split(":", 1)[1]


def native_read(target: str) -> None:
    name = native_target(target)
    print(tmux("capture-pane", "-p", "-S", "-200", "-t", f"{TMUX_SESSION}:{name}").stdout.rstrip())


def native_prompt(target: str, prompt: str) -> None:
    if not prompt.strip():
        raise SystemExit("Prompt text is required.")
    name = native_target(target)
    buffer_name = "nbshell-prompt"
    tmux("load-buffer", "-b", buffer_name, "-", input_text=prompt)
    tmux("paste-buffer", "-b", buffer_name, "-d", "-t", f"{TMUX_SESSION}:{name}")
    time.sleep(0.08)
    tmux("send-keys", "-t", f"{TMUX_SESSION}:{name}", "Enter")
    state = load_native_state()
    for item in state.get("sessions", []):
        if item.get("name") == name:
            item.update(status="working", stableChecks=0, outputHash="")
    save_native_state(state)
    print("Prompt sent.")


def native_start(agent_id: str, project: str | None, prompt: str) -> None:
    if agent_id not in AGENTS or not shutil.which(AGENTS[agent_id]["binary"]):
        raise SystemExit(f"{AGENTS.get(agent_id, {}).get('name', agent_id)} is not installed.")
    config = load_config()
    cwd = Path(project or config.get("lastProject") or Path.cwd()).expanduser().resolve()
    if not cwd.is_dir():
        raise SystemExit(f"Project directory does not exist: {cwd}")
    name = f"{agent_id}-{int(time.time()):x}"[-28:]
    command = [AGENTS[agent_id]["binary"], *profile_args(agent_id, str(config.get("profile", "balanced")))]
    route = config.get("modelProfiles", {}).get(str(config.get("modelProfile", "cloud")), {})
    if agent_id == "opencode" and route.get("model"):
        command += ["--model", str(route["model"])]
    shell_command = "exec " + " ".join(shlex.quote(part) for part in command)
    server = tmux("has-session", "-t", TMUX_SESSION, check=False)
    if server.returncode:
        tmux("new-session", "-d", "-x", "180", "-y", "52", "-s", TMUX_SESSION, "-n", name, "-c", str(cwd), shell_command, timeout=15)
        tmux("set-option", "-t", TMUX_SESSION, "remain-on-exit", "on")
        tmux("set-option", "-t", TMUX_SESSION, "status", "off")
    else:
        tmux("new-window", "-d", "-t", TMUX_SESSION, "-n", name, "-c", str(cwd), shell_command, timeout=15)
    state = load_native_state()
    state.setdefault("sessions", []).append({
        "name": name, "agent": agent_id, "project": str(cwd),
        "label": f"{AGENTS[agent_id]['name']} · {cwd.name}", "status": "working",
        "createdAt": int(time.time()), "stableChecks": 0, "outputHash": "",
    })
    save_native_state(state)
    config["lastProject"] = str(cwd)
    save_config(config)
    if prompt.strip():
        time.sleep(3)
        native_prompt("nbshell:" + name, prompt)
    print(f"Started {AGENTS[agent_id]['name']} in {cwd.name} with the nbshell backend.")


def native_restore(target: str) -> None:
    name = native_target(target)
    state = load_native_state()
    item = next((row for row in state.get("sessions", []) if row.get("name") == name), None)
    if not item:
        raise SystemExit("Native session metadata was not found.")
    agent_id = str(item.get("agent", ""))
    if agent_id not in AGENTS or not shutil.which(AGENTS[agent_id]["binary"]):
        raise SystemExit(f"{AGENTS.get(agent_id, {}).get('name', agent_id)} is not installed.")
    cwd = Path(str(item.get("project") or Path.home())).expanduser()
    resume = {"codex": ["resume", "--last"], "claude": ["--continue"], "agy": ["--continue"]}.get(agent_id, [])
    command = [AGENTS[agent_id]["binary"], *profile_args(agent_id, str(load_config().get("profile", "balanced"))), *resume]
    shell_command = "exec " + " ".join(shlex.quote(part) for part in command)
    server = tmux("has-session", "-t", TMUX_SESSION, check=False)
    if server.returncode:
        tmux("new-session", "-d", "-x", "180", "-y", "52", "-s", TMUX_SESSION, "-n", name, "-c", str(cwd), shell_command, timeout=15)
        tmux("set-option", "-t", TMUX_SESSION, "remain-on-exit", "on")
        tmux("set-option", "-t", TMUX_SESSION, "status", "off")
    else:
        tmux("new-window", "-d", "-t", TMUX_SESSION, "-n", name, "-c", str(cwd), shell_command, timeout=15)
    item.update(status="working", stableChecks=0, outputHash="")
    save_native_state(state)
    print(f"Restored {AGENTS[agent_id]['name']} in {cwd.name}.")


def native_close(target: str) -> None:
    name = native_target(target)
    tmux("kill-window", "-t", f"{TMUX_SESSION}:{name}", check=False)
    state = load_native_state()
    before = len(state.get("sessions", []))
    state["sessions"] = [item for item in state.get("sessions", []) if item.get("name") != name]
    save_native_state(state)
    if len(state["sessions"]) == before:
        raise SystemExit("Native session metadata was not found.")
    print("Session closed and removed.")


def agent_rows() -> list[dict]:
    rows = []
    for agent_id, spec in AGENTS.items():
        path = shutil.which(spec["binary"])
        rows.append({"id": agent_id, **spec, "installed": bool(path), "path": path or ""})
    return rows


def ollama_status() -> dict:
    host = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
    try:
        with urllib.request.urlopen(host + "/api/tags", timeout=1.2) as response:
            body = json.load(response)
        models = [str(row.get("name", "")) for row in body.get("models", []) if row.get("name")]
        return {"installed": bool(shutil.which("ollama")), "running": True, "host": host, "models": models}
    except (OSError, ValueError, urllib.error.URLError):
        return {"installed": bool(shutil.which("ollama")), "running": False, "host": host, "models": []}


def herdr_sessions() -> list[dict]:
    if not shutil.which("herdr"):
        return []
    attempts = (["herdr", "agent", "list", "--json"], ["herdr", "agent", "list"])
    for command in attempts:
        result = subprocess.run(command, text=True, capture_output=True, timeout=3, check=False)
        if result.returncode:
            continue
        try:
            data = json.loads(result.stdout)
            raw = data.get("result", {}).get("agents", data.get("agents", []))
            return [{
                "id": "herdr:" + str(row.get("agent_id") or row.get("id") or row.get("pane_id") or ""),
                "name": str(row.get("agent") or row.get("name") or "Agent"),
                "status": str(row.get("agent_status") or row.get("status") or "unknown"),
                "project": str(row.get("cwd") or ""),
                "title": str(row.get("terminal_title_stripped") or row.get("title") or ""),
                "focused": bool(row.get("focused", False)),
                "workspace": str(row.get("workspace_id") or ""),
                "backend": "herdr",
            } for row in raw]
        except (ValueError, AttributeError):
            return []
    return []


def herdr_result(*args: str, timeout: float = 8) -> dict:
    if not shutil.which("herdr"):
        raise SystemExit("Herdr is not installed.")
    result = subprocess.run(["herdr", *args], text=True, capture_output=True, timeout=timeout, check=False)
    if result.returncode:
        try:
            message = json.loads(result.stderr).get("error", {}).get("message", "")
        except (ValueError, AttributeError):
            message = result.stderr.strip()
        raise SystemExit(message or f"Herdr command failed: {' '.join(args[:2])}")
    try:
        return json.loads(result.stdout) if result.stdout.strip() else {}
    except ValueError:
        return {"text": result.stdout.strip()}


def herdr_session_read(target: str) -> None:
    target = target.removeprefix("herdr:")
    data = herdr_result("agent", "read", target, "--source", "recent-unwrapped", "--lines", "100")
    result = data.get("result", {})
    print(str(result.get("text") or result.get("output") or data.get("text") or ""))


def herdr_session_prompt(target: str, prompt: str) -> None:
    target = target.removeprefix("herdr:")
    if not prompt.strip():
        raise SystemExit("Prompt text is required.")
    herdr_result("agent", "prompt", target, prompt, timeout=10)
    print("Prompt sent.")


def herdr_quake_start(agent_id: str, project: str | None, prompt: str) -> None:
    if agent_id not in AGENTS:
        raise SystemExit(f"Unknown agent: {agent_id}")
    if not shutil.which(AGENTS[agent_id]["binary"]):
        raise SystemExit(f"{AGENTS[agent_id]['name']} is not installed.")
    config = load_config()
    cwd = Path(project or config.get("lastProject") or Path.cwd()).expanduser().resolve()
    if not cwd.is_dir():
        raise SystemExit(f"Project directory does not exist: {cwd}")
    sessions = herdr_sessions()
    workspace = str((next((row for row in sessions if row.get("focused")), None) or (sessions[0] if sessions else {})).get("workspace") or "")
    if not workspace:
        workspaces = herdr_result("workspace", "list").get("result", {}).get("workspaces", [])
        if workspaces:
            workspace = str(workspaces[0].get("workspace_id") or workspaces[0].get("id") or "")
    if not workspace:
        created = herdr_result("workspace", "create", "--cwd", str(cwd), "--label", "agents", "--no-focus")
        workspace = str(created.get("result", {}).get("workspace", {}).get("workspace_id", ""))
        pane = str(created.get("result", {}).get("root_pane", {}).get("pane_id", ""))
    else:
        created = herdr_result("tab", "create", "--workspace", workspace, "--cwd", str(cwd), "--label", f"{agent_id} · {cwd.name}", "--no-focus")
        pane = str(created.get("result", {}).get("root_pane", {}).get("pane_id", ""))
    if not pane:
        raise SystemExit("Herdr did not return a new terminal pane.")
    name = f"quake_{agent_id}_{int(time.time()) & 0xfffff:x}"
    command = ["agent", "start", name, "--kind", agent_id, "--pane", pane, "--timeout", "60000"]
    native = profile_args(agent_id, str(config.get("profile", "balanced")))
    if native:
        command += ["--", *native]
    herdr_result(*command, timeout=65)
    config["lastProject"] = str(cwd)
    save_config(config)
    if prompt.strip():
        herdr_result("agent", "prompt", name, prompt, timeout=10)
    print(f"Started {AGENTS[agent_id]['name']} in {cwd.name}.")


def projects(config: dict) -> list[dict]:
    base = Path(config.get("projectsDir") or Path.home() / "projects").expanduser()
    home = Path.home()
    rows = [{"name": "Home", "path": str(home), "git": (home / ".git").exists()}]
    if base.is_dir():
        for path in sorted((p for p in base.iterdir() if p.is_dir()), key=lambda p: p.name.lower()):
            rows.append({"name": path.name, "path": str(path), "git": (path / ".git").exists()})
    last_raw = str(config.get("lastProject") or "").strip()
    if last_raw:
        last = Path(last_raw).expanduser()
        if last.is_dir() and all(row["path"] != str(last) for row in rows):
            rows.insert(0, {"name": last.name, "path": str(last), "git": (last / ".git").exists()})
    return rows


def full_status() -> dict:
    config = load_config()
    rows = agent_rows()
    native = native_sessions()
    legacy = herdr_sessions()
    installed = {row["id"] for row in rows if row["installed"]}
    if config["defaultAgent"] not in installed and installed:
        config["defaultAgent"] = next(row["id"] for row in rows if row["installed"])
    return {
        "config": config,
        "agents": rows,
        "ollama": ollama_status(),
        "sessions": native + legacy,
        "sessionBackend": {
            "native": bool(shutil.which("tmux")),
            "name": "nbshell" if shutil.which("tmux") else "herdr fallback",
            "migration": bool(legacy),
        },
        "projects": projects(config),
    }


def terminal_command(config: dict) -> list[str]:
    configured = str(config.get("terminal") or "").strip()
    terminal = configured or os.environ.get("TERMINAL", "")
    if terminal:
        binary = shutil.which(terminal.split()[0])
        if binary:
            return [binary, *terminal.split()[1:]]
    for candidate in ("ghostty", "foot", "kitty", "alacritty"):
        binary = shutil.which(candidate)
        if binary:
            return [binary]
    raise SystemExit("No supported terminal found. Set terminal in ~/.config/nbshell/agents.json.")


def native_focus(target: str) -> None:
    name = native_target(target)
    config = load_config()
    terminal = terminal_command(config)
    command = ["tmux", "-L", TMUX_SOCKET, "attach-session", "-t", f"{TMUX_SESSION}:{name}"]
    base = Path(terminal[0]).name
    if base == "ghostty":
        terminal += ["--gtk-single-instance=false", "--class=dev.nerdi.nbshell.agent.native", "--title=Agent Console Session", "-e", *command]
    elif base in {"foot", "kitty"}:
        terminal += ["--app-id=dev.nerdi.nbshell.agent.native", "-T", "Agent Console Session", *command]
    elif base == "alacritty":
        terminal += ["--class", "dev.nerdi.nbshell.agent.native", "--title", "Agent Console Session", "-e", *command]
    else:
        terminal += ["-e", *command]
    subprocess.Popen(terminal, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def profile_args(agent_id: str, profile: str) -> list[str]:
    # Profiles map to each installed CLI's native vocabulary. The dangerous
    # Codex bypass is only reachable through the visibly selected autonomous
    # profile; fresh installations still default to balanced.
    profiles = {
        "safe": {
            "codex": ["--ask-for-approval", "untrusted", "--sandbox", "workspace-write"],
            "claude": ["--permission-mode", "manual"],
            "gemini": ["--approval-mode", "default"],
        },
        "balanced": {
            "codex": ["--approve-for-me"],
            "claude": ["--permission-mode", "acceptEdits"],
            "gemini": ["--approval-mode", "auto_edit"],
        },
        "autonomous": {
            "codex": ["--dangerously-bypass-approvals-and-sandbox"],
            "claude": ["--permission-mode", "auto"],
            "opencode": ["--auto"],
            "gemini": ["--approval-mode", "yolo"],
            "copilot": ["--allow-all"],
        },
    }
    return profiles.get(profile, {}).get(agent_id, [])


def prompt_args(agent_id: str, prompt: str) -> list[str]:
    if not prompt:
        return []
    mode = AGENTS[agent_id]["prompt"]
    if mode == "opencode":
        return ["--prompt", prompt]
    if mode == "gemini":
        return ["--prompt-interactive", prompt]
    if mode == "copilot":
        return ["--interactive", prompt]
    return [prompt]


def launch(agent_id: str | None, project: str | None, prompt: str = "", quick: bool = False) -> None:
    config = load_config()
    route = config.get("modelProfiles", {}).get(str(config.get("modelProfile", "cloud")), {})
    agent_id = agent_id or str(route.get("agent") or config["defaultAgent"])
    if agent_id not in AGENTS:
        raise SystemExit(f"Unknown agent: {agent_id}")
    binary = shutil.which(AGENTS[agent_id]["binary"])
    if not binary:
        raise SystemExit(f"{AGENTS[agent_id]['name']} is not installed ({AGENTS[agent_id]['binary']}).")
    quick_project = Path.home() / "projects" / "nbshell"
    cwd = Path(
        project
        or (quick_project if quick and quick_project.is_dir() else "")
        or config.get("lastProject")
        or Path.cwd()
    ).expanduser().resolve()
    if not cwd.is_dir():
        raise SystemExit(f"Project directory does not exist: {cwd}")
    config["lastProject"] = str(cwd)
    save_config(config)
    model_args = []
    routed_model = str(route.get("model") or "")
    if routed_model and agent_id == "opencode":
        model_args = ["--model", routed_model]
    command = [binary, *profile_args(agent_id, str(config["profile"])), *model_args, *prompt_args(agent_id, prompt)]
    shell_cmd = "exec " + " ".join(shlex.quote(part) for part in command)
    terminal = terminal_command(config)
    name = f"dev.nerdi.nbshell.agent.{'quick.' if quick else ''}{agent_id}"
    title = ("Quick Agent · " if quick else "") + AGENTS[agent_id]["name"]
    base = Path(terminal[0]).name
    if base == "ghostty":
        # Ghostty forwards CLI arguments to its existing process by default,
        # which keeps the original Wayland app-id. A separate GTK instance is
        # required for Niri to see the per-agent class and apply window rules.
        terminal += ["--gtk-single-instance=false", "--class=" + name, "--title=" + title, "-e", "sh", "-lc", shell_cmd]
    elif base in {"foot", "kitty"}:
        terminal += ["--app-id=" + name, "-T", title, "sh", "-lc", shell_cmd]
    elif base == "alacritty":
        terminal += ["--class", name, "--title", title, "-e", "sh", "-lc", shell_cmd]
    else:
        terminal += ["-e", "sh", "-lc", shell_cmd]
    subprocess.Popen(terminal, cwd=cwd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def install_agent(agent_id: str) -> None:
    if agent_id not in AGENTS:
        raise SystemExit(f"Unknown agent: {agent_id}")
    spec = AGENTS[agent_id]
    if shutil.which(spec["binary"]):
        print(f"{spec['name']} is already installed.")
        return
    command = str(spec.get("install") or "")
    if not command:
        raise SystemExit(f"No installation command is known for {spec['name']}.")
    config = load_config()
    terminal = terminal_command(config)
    prompt = f"Install {spec['name']} with: {command} [y/N] "
    script = f"printf '%s' {shlex.quote(prompt)}; read -r answer; case $answer in y|Y) {command} ;; *) echo 'Cancelled.' ;; esac; printf '\\nPress Enter to close.'; read -r _"
    base = Path(terminal[0]).name
    if base == "ghostty": terminal += ["--gtk-single-instance=false", "--class=dev.nerdi.nbshell.agent.installer", "--title=Install " + spec["name"], "-e", "sh", "-lc", script]
    elif base in {"foot", "kitty"}: terminal += ["--app-id=dev.nerdi.nbshell.agent.installer", "-T", "Install " + spec["name"], "sh", "-lc", script]
    elif base == "alacritty": terminal += ["--class", "dev.nerdi.nbshell.agent.installer", "--title", "Install " + spec["name"], "-e", "sh", "-lc", script]
    else: terminal += ["-e", "sh", "-lc", script]
    subprocess.Popen(terminal, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def set_value(key: str, value: str) -> None:
    config = load_config()
    config[key] = value
    save_config(config)
    print(value)


def set_profile_model(profile: str, model: str) -> None:
    config = load_config()
    routes = DEFAULT_CONFIG["modelProfiles"] | dict(config.get("modelProfiles", {}))
    route = dict(routes.get(profile, {}))
    route["model"] = model
    routes[profile] = route
    config["modelProfiles"] = routes
    save_config(config)
    print(f"{profile}: {model or '(agent default)'}")


def ollama_control(action: str) -> None:
    if action == "status":
        print(json.dumps(ollama_status()))
        return
    if action == "start":
        if not shutil.which("ollama"):
            raise SystemExit("Ollama is not installed.")
        if ollama_status()["running"]:
            print("Ollama is already running.")
            return
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        log = open(STATE_DIR / "ollama.log", "ab")
        proc = subprocess.Popen(["ollama", "serve"], start_new_session=True, stdout=log, stderr=log)
        OLLAMA_PID.write_text(str(proc.pid) + "\n")
        print("Ollama started.")
        return
    if action == "stop":
        try:
            pid = int(OLLAMA_PID.read_text().strip())
            os.kill(pid, signal.SIGTERM)
            OLLAMA_PID.unlink(missing_ok=True)
            print("Ollama stopped.")
        except (OSError, ValueError):
            raise SystemExit("No nbshell-managed Ollama process found.")


def doctor() -> int:
    state = full_status()
    problems = 0
    print("AGENTS")
    for row in state["agents"]:
        mark = "ok" if row["installed"] else "missing"
        print(f"  {row['id']:<10} {mark:<8} {row['path'] or row['binary']}")
    default = state["config"]["defaultAgent"]
    if not next((row["installed"] for row in state["agents"] if row["id"] == default), False):
        problems += 1
        print(f"\nERROR  Default agent is unavailable: {default}")
    print(f"\nPROFILE  {state['config']['profile']} / {state['config']['modelProfile']}")
    ollama = state["ollama"]
    print(f"OLLAMA   {'running' if ollama['running'] else ('stopped' if ollama['installed'] else 'not installed')}")
    backend = state["sessionBackend"]
    native_count = sum(row.get("backend") == "nbshell" for row in state["sessions"])
    legacy_count = sum(row.get("backend") == "herdr" for row in state["sessions"])
    print(f"BACKEND  {backend['name']} ({native_count} native session(s))")
    if legacy_count:
        print(f"LEGACY   {legacy_count} Herdr session(s) available for migration")
    print(f"PROJECTS {len(state['projects'])} found")
    return problems


def herdr_workspace(template: str, project: str | None, new_tab: bool = False) -> None:
    pane = os.environ.get("HERDR_PANE_ID", "")
    tab = os.environ.get("HERDR_TAB_ID", "")
    config = load_config()
    cwd = str(Path(project or config.get("lastProject") or Path.cwd()).expanduser().resolve())
    if new_tab:
        workspace_id = ""
        current = subprocess.run(["herdr", "pane", "current"], text=True, capture_output=True, check=False)
        if current.returncode == 0:
            try:
                workspace_id = str(json.loads(current.stdout).get("result", {}).get("pane", {}).get("workspace_id", ""))
            except (ValueError, AttributeError):
                pass
        if not workspace_id:
            sessions = herdr_sessions()
            source = next((row for row in sessions if row["focused"]), sessions[0] if sessions else None)
            workspace_id = str(source.get("workspace") or "") if source else ""
        if not workspace_id:
            raise SystemExit("No active Herdr workspace found. Open Herdr once, then try again.")
        result = subprocess.run(
            ["herdr", "tab", "create", "--workspace", workspace_id, "--cwd", cwd,
             "--label", Path(cwd).name, "--focus"],
            text=True, capture_output=True, check=True,
        )
        created = json.loads(result.stdout).get("result", {})
        pane = str(created.get("root_pane", {}).get("pane_id", ""))
        tab = str(created.get("tab", {}).get("tab_id", ""))
    if not pane:
        raise SystemExit("Workspace templates must be started inside Herdr or with --new-tab.")
    agent = str(config["defaultAgent"])
    binary = AGENTS.get(agent, {}).get("binary", agent)
    agent_cmd = " ".join(shlex.quote(x) for x in [binary, *profile_args(agent, str(config["profile"]))])

    def split(source: str, direction: str, ratio: str) -> str:
        result = subprocess.run(
            ["herdr", "pane", "split", source, "--direction", direction, "--ratio", ratio, "--cwd", cwd, "--no-focus"],
            text=True, capture_output=True, check=True,
        )
        data = json.loads(result.stdout)
        return str(data.get("result", {}).get("pane", {}).get("pane_id", ""))

    if tab:
        subprocess.run(["herdr", "tab", "rename", tab, Path(cwd).name], check=False)
    terminal_pane = split(pane, "down", "0.82")
    agent_pane = split(pane, "right", "0.70")
    subprocess.run(["herdr", "pane", "run", pane, os.environ.get("EDITOR", "nvim") + " ."], check=True)
    subprocess.run(["herdr", "pane", "run", agent_pane, agent_cmd], check=True)
    if template == "review":
        review_pane = split(agent_pane, "down", "0.50")
        review_prompt = "Review the current git diff. Do not edit files; report correctness, risks, and missing tests."
        review_cmd = agent_cmd + " " + shlex.quote(review_prompt)
        subprocess.run(["herdr", "pane", "run", review_pane, review_cmd], check=True)
    elif template == "pair":
        secondary = "opencode" if agent != "opencode" and shutil.which("opencode") else "codex"
        secondary_spec = AGENTS[secondary]
        secondary_cmd = [secondary_spec["binary"], *profile_args(secondary, str(config["profile"]))]
        if secondary == "opencode":
            local_route = config.get("modelProfiles", {}).get("local", {})
            local_model = str(local_route.get("model") or "")
            if local_model:
                secondary_cmd += ["--model", local_model]
        pair_pane = split(agent_pane, "down", "0.50")
        subprocess.run(["herdr", "pane", "run", pair_pane, " ".join(shlex.quote(x) for x in secondary_cmd)], check=True)
    subprocess.run(["herdr", "pane", "run", terminal_pane, "git status --short; exec $SHELL"], check=True)
    print(f"Created {template} workspace for {Path(cwd).name}.")


def main() -> int:
    parser = argparse.ArgumentParser(description="nbshell AI agent control")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("status")
    list_p = sub.add_parser("list"); list_p.add_argument("--json", action="store_true")
    projects_p = sub.add_parser("projects"); projects_p.add_argument("--json", action="store_true")
    sessions_p = sub.add_parser("sessions"); sessions_p.add_argument("--json", action="store_true")
    sub.add_parser("doctor")
    default = sub.add_parser("default"); default.add_argument("agent", nargs="?")
    profile = sub.add_parser("profile"); profile.add_argument("profile", nargs="?", choices=["safe", "balanced", "autonomous"])
    model = sub.add_parser("model-profile"); model.add_argument("profile", nargs="?", choices=["local", "cloud", "private", "fast", "strong"])
    route_model = sub.add_parser("model"); route_model.add_argument("profile", choices=["local", "cloud", "private", "fast", "strong"]); route_model.add_argument("model")
    launch_p = sub.add_parser("launch"); launch_p.add_argument("agent", nargs="?"); launch_p.add_argument("--project"); launch_p.add_argument("--prompt", default="")
    quick_p = sub.add_parser("quick"); quick_p.add_argument("--project"); quick_p.add_argument("--prompt", default="")
    install_p = sub.add_parser("install"); install_p.add_argument("agent", choices=sorted(AGENTS))
    prompt_p = sub.add_parser("prompt"); prompt_p.add_argument("prompt", nargs="+"); prompt_p.add_argument("--agent"); prompt_p.add_argument("--project")
    ollama = sub.add_parser("ollama"); ollama.add_argument("action", nargs="?", default="status", choices=["status", "start", "stop"])
    workspace = sub.add_parser("workspace"); workspace.add_argument("template", choices=["dev", "review", "pair"]); workspace.add_argument("--project"); workspace.add_argument("--new-tab", action="store_true")
    session_read = sub.add_parser("session-read"); session_read.add_argument("target")
    session_prompt = sub.add_parser("session-prompt"); session_prompt.add_argument("target"); session_prompt.add_argument("prompt")
    session_focus = sub.add_parser("session-focus"); session_focus.add_argument("target")
    session_restore = sub.add_parser("session-restore"); session_restore.add_argument("target")
    session_close = sub.add_parser("session-close"); session_close.add_argument("target")
    quake_start = sub.add_parser("quake-start"); quake_start.add_argument("agent", choices=sorted(AGENTS)); quake_start.add_argument("--project"); quake_start.add_argument("--prompt", default="")
    args = parser.parse_args()
    config = load_config()
    command = args.command or "status"
    if command == "status": print(json.dumps(full_status())); return 0
    if command == "list":
        rows = agent_rows()
        if args.json: print(json.dumps(rows))
        else:
            for row in rows: print(f"{row['id']:<10} {'installed' if row['installed'] else 'missing':<10} {row['name']}")
        return 0
    if command == "projects":
        rows = projects(config)
        if args.json: print(json.dumps(rows))
        else:
            for row in rows: print(row["path"])
        return 0
    if command == "sessions":
        rows = native_sessions() + herdr_sessions()
        if args.json: print(json.dumps(rows))
        else:
            for row in rows: print(f"{row['id']:<12} {row['name']:<10} {row['status']:<12} {row['project']}")
        return 0
    if command == "doctor": return doctor()
    if command == "default":
        if args.agent is None: print(config["defaultAgent"]); return 0
        if args.agent not in AGENTS: raise SystemExit(f"Unknown agent: {args.agent}")
        set_value("defaultAgent", args.agent); return 0
    if command == "profile":
        if args.profile is None: print(config["profile"]); return 0
        set_value("profile", args.profile); return 0
    if command == "model-profile":
        if args.profile is None: print(config["modelProfile"]); return 0
        set_value("modelProfile", args.profile); return 0
    if command == "model": set_profile_model(args.profile, args.model); return 0
    if command == "launch": launch(args.agent, args.project, args.prompt); return 0
    if command == "quick": launch(None, args.project, args.prompt, quick=True); return 0
    if command == "install": install_agent(args.agent); return 0
    if command == "prompt": launch(args.agent, args.project, " ".join(args.prompt)); return 0
    if command == "ollama": ollama_control(args.action); return 0
    if command == "workspace": herdr_workspace(args.template, args.project, args.new_tab); return 0
    if command == "session-read":
        native_read(args.target) if args.target.startswith("nbshell:") else herdr_session_read(args.target)
        return 0
    if command == "session-prompt":
        native_prompt(args.target, args.prompt) if args.target.startswith("nbshell:") else herdr_session_prompt(args.target, args.prompt)
        return 0
    if command == "session-focus":
        native_focus(args.target) if args.target.startswith("nbshell:") else herdr_result("agent", "focus", args.target.removeprefix("herdr:"))
        return 0
    if command == "session-restore": native_restore(args.target); return 0
    if command == "session-close": native_close(args.target); return 0
    if command == "quake-start":
        native_start(args.agent, args.project, args.prompt) if shutil.which("tmux") else herdr_quake_start(args.agent, args.project, args.prompt)
        return 0
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.TimeoutExpired:
        raise SystemExit("Agent status request timed out.")
