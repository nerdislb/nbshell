#!/usr/bin/env python3
"""nbshell agent registry, launcher, local-model status, and Herdr bridge."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import signal
import sqlite3
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
SKILL_SOURCE = Path(__file__).resolve().parents[1] / "skills" / "nbshell"
HERMES_PILOT = Path.home() / ".local/share/nbshell/hermes-pilot"
HERMES_BROKER = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nbshell/hermes-broker/server.py"
HERMES_JOBS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nbshell/hermes-jobs/manager.py"
HERMES_TEAMS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nbshell/hermes-team/manager.py"
HERMES_BROKER_TOOLS = [
    "ask_claude", "ask_codex", "ask_gemini", "start_claude_job", "start_codex_job",
    "start_gemini_job", "review_agent_job", "agent_job_status", "start_supervised_team", "supervised_team_status",
]

HERMES_PROVIDERS = {
    "codex": {"provider": "openai-codex", "model": "gpt-5.6-sol", "label": "Codex", "native": True},
    "claude": {"provider": "anthropic", "model": "anthropic/claude-sonnet-4.6", "label": "Claude", "native": True},
    "gemini": {"provider": "agy", "model": "", "label": "Gemini", "native": False},
}
HERMES_TOOLSETS = {
    "restricted": "file,nbshell-ai-broker",
    "research": "file,web,nbshell-ai-broker",
    "workspace": "file,web,terminal,nbshell-ai-broker",
}


def antigravity_binary() -> str:
    """Prefer the vendor binary so user wrappers cannot widen Hub permissions."""
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    vendor = data_home / "antigravity/bin/agy"
    if vendor.is_file() and os.access(vendor, os.X_OK):
        return str(vendor)
    return shutil.which("agy") or ""

AGENTS = {
    "codex": {"name": "Codex", "binary": "codex", "kind": "cloud", "prompt": "positional", "glyph": "code", "install": "npm install -g @openai/codex"},
    "claude": {"name": "Claude Code", "binary": "claude", "kind": "cloud", "prompt": "positional", "glyph": "claude", "install": "npm install -g @anthropic-ai/claude-code"},
    "agy": {"name": "Antigravity", "binary": "agy", "kind": "cloud", "prompt": "positional", "glyph": "spark", "install": ""},
    "opencode": {"name": "OpenCode", "binary": "opencode", "kind": "hybrid", "prompt": "opencode", "glyph": "terminal", "install": "paru -S opencode"},
    "gemini": {"name": "Gemini CLI", "binary": "gemini", "kind": "cloud", "prompt": "gemini", "glyph": "spark", "install": "npm install -g @google/gemini-cli"},
    "copilot": {"name": "GitHub Copilot", "binary": "copilot", "kind": "cloud", "prompt": "copilot", "glyph": "code", "install": "npm install -g @github/copilot"},
    "pi": {"name": "Pi", "binary": "pi", "kind": "hybrid", "prompt": "positional", "glyph": "terminal", "install": "npm install -g @mariozechner/pi-coding-agent"},
    "hermes": {"name": "Hermes", "binary": "hermes", "kind": "pilot", "prompt": "hermes", "glyph": "spark", "install": ""},
}

DEFAULT_CONFIG = {
    "defaultAgent": "codex",
    "profile": "balanced",
    "modelProfile": "cloud",
    "lastProject": "",
    "projectsDir": str(Path.home() / "projects"),
    "terminal": "",
    "hermesProvider": "codex",
    "hermesMode": "restricted",
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


def hermes_sessions(home: Path, limit: int = 4) -> list[dict]:
    database = home / "state.db"
    if not database.is_file():
        return []
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=0.2)
        rows = connection.execute(
            """SELECT id, model, COALESCE(last_activity_at, started_at),
                      message_count, tool_call_count, input_tokens, output_tokens
                 FROM sessions
                WHERE source = 'cli' AND cwd = ? AND archived = 0 AND hidden = 0
                ORDER BY COALESCE(last_activity_at, started_at) DESC LIMIT ?""",
            (str(HERMES_PILOT), limit),
        ).fetchall()
        connection.close()
        return [{
            "id": str(row[0]), "model": str(row[1] or ""), "lastActive": float(row[2] or 0),
            "messages": int(row[3] or 0), "tools": int(row[4] or 0),
            "inputTokens": int(row[5] or 0), "outputTokens": int(row[6] or 0),
        } for row in rows]
    except (OSError, sqlite3.Error, TypeError, ValueError):
        return []


def hermes_status(config: dict) -> dict:
    binary = shutil.which("hermes")
    home = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
    selected = str(config.get("hermesProvider") or "codex")
    if selected not in HERMES_PROVIDERS:
        selected = "codex"
    mode = str(config.get("hermesMode") or "restricted")
    if mode not in HERMES_TOOLSETS:
        mode = "restricted"
    result = {
        "installed": bool(binary), "version": "", "authenticated": False,
        "gateway": "inactive", "provider": "", "model": "", "selected": selected,
        "mode": mode, "running": False, "sessions": [], "providers": {},
        "jobs": [], "jobsRunning": 0, "teams": [], "teamsRunning": 0, "teamsAttention": 0,
    }
    if not binary:
        return result
    try:
        package = (home / "hermes-agent/pyproject.toml").read_text(errors="replace")
        for line in package.splitlines():
            if line.startswith("version = "):
                result["version"] = "v" + line.split('"', 2)[1]
                break
        # Authentication data remains opaque: only the protected store's
        # existence is observed, never its credential-bearing contents.
        result["authenticated"] = (home / "auth.json").is_file()
        config = (home / "config.yaml").read_text(errors="replace")
        in_model = False
        for line in config.splitlines():
            if line == "model:":
                in_model = True
                continue
            if in_model and line and not line.startswith(" "):
                break
            if in_model and line.startswith("  provider:"):
                result["provider"] = line.split(":", 1)[1].strip().strip('"\'')
            if in_model and line.startswith("  default:"):
                result["model"] = line.split(":", 1)[1].strip().strip('"\'')
        gateway = subprocess.run(["systemctl", "--user", "is-active", "hermes-gateway.service"],
                                 text=True, capture_output=True, timeout=2, check=False)
        result["gateway"] = gateway.stdout.strip() or "inactive"
        result["sessions"] = hermes_sessions(home)
        process = subprocess.run(["pgrep", "-f", "hermes --tui.*nbshell/hermes-pilot"],
                                 text=True, capture_output=True, timeout=1, check=False)
        result["running"] = process.returncode == 0
        if HERMES_JOBS.is_file():
            jobs = subprocess.run([sys.executable, str(HERMES_JOBS), "list"],
                                  text=True, capture_output=True, timeout=3, check=False)
            if jobs.returncode == 0:
                payload = json.loads(jobs.stdout)
                result["jobs"] = payload.get("jobs", [])
                result["jobsRunning"] = int(payload.get("running", 0))
        if HERMES_TEAMS.is_file():
            teams = subprocess.run([sys.executable, str(HERMES_TEAMS), "list"],
                                   text=True, capture_output=True, timeout=3, check=False)
            if teams.returncode == 0:
                payload = json.loads(teams.stdout)
                result["teams"] = payload.get("teams", [])
                result["teamsRunning"] = int(payload.get("running", 0))
                result["teamsAttention"] = int(payload.get("attention", 0))
    except (OSError, IndexError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired):
        pass
    result["providers"] = {
        "codex": {"label": "Codex", "ready": (home / "auth.json").is_file(), "native": True},
        "claude": {"label": "Claude", "ready": (Path.home() / ".claude/.credentials.json").is_file(), "native": True},
        "gemini": {"label": "Gemini", "ready": bool(antigravity_binary()), "native": False},
    }
    return result


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
    sessions = herdr_sessions()
    installed = {row["id"] for row in rows if row["installed"]}
    if config["defaultAgent"] not in installed and installed:
        config["defaultAgent"] = next(row["id"] for row in rows if row["installed"])
    return {
        "config": config,
        "agents": rows,
        "ollama": ollama_status(),
        "hermes": hermes_status(config),
        "sessions": sessions,
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
    if mode == "hermes":
        return []
    return [prompt]


def launch(agent_id: str | None, project: str | None, prompt: str = "", quick: bool = False,
           resume: str = "") -> None:
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
    launch_env = None
    if agent_id == "hermes":
        provider_id = str(config.get("hermesProvider") or "codex")
        mode = str(config.get("hermesMode") or "restricted")
        provider = HERMES_PROVIDERS.get(provider_id, HERMES_PROVIDERS["codex"])
        toolsets = HERMES_TOOLSETS.get(mode, HERMES_TOOLSETS["restricted"])
        cwd = HERMES_PILOT
        launch_env = os.environ.copy()
        launch_env["HERMES_WRITE_SAFE_ROOT"] = str(HERMES_PILOT)
        if provider["native"]:
            command = [binary, "--tui", "--in", str(HERMES_PILOT), "--toolsets", toolsets,
                       "--provider", str(provider["provider"]), "--model", str(provider["model"])]
            if resume:
                command += ["--resume", resume, "--no-restore-cwd"]
        else:
            if resume:
                raise SystemExit("Gemini uses an external Antigravity session and cannot resume a Hermes session.")
            agy = antigravity_binary()
            if not agy:
                raise SystemExit("Antigravity is not installed.")
            command = [agy, "--sandbox", "--mode", "accept-edits" if mode == "workspace" else "plan"]
    shell_cmd = "exec " + " ".join(shlex.quote(part) for part in command)
    terminal = terminal_command(config)
    name = f"dev.nerdi.nbshell.agent.{'quick.' if quick else ''}{agent_id}"
    title = ("Quick Agent · " if quick else "") + AGENTS[agent_id]["name"]
    if agent_id == "hermes":
        title = "Hermes Hub · " + HERMES_PROVIDERS.get(
            str(config.get("hermesProvider") or "codex"), HERMES_PROVIDERS["codex"]
        )["label"]
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
    subprocess.Popen(terminal, cwd=cwd, env=launch_env, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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


def set_hermes_choice(key: str, value: str, allowed: dict) -> None:
    if value not in allowed:
        raise SystemExit(f"Unknown Hermes {key}: {value}")
    config_key = "hermesProvider" if key == "provider" else "hermesMode"
    set_value(config_key, value)


def hermes_broker_control(action: str) -> None:
    hermes = shutil.which("hermes")
    hermes_home = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
    python = hermes_home / "hermes-agent/venv/bin/python"
    if not hermes:
        raise SystemExit("Hermes is not installed.")
    if action == "status":
        result = subprocess.run([hermes, "config", "get", "mcp_servers.nbshell-ai-broker.enabled"],
                                text=True, capture_output=True, timeout=5, check=False)
        enabled = result.returncode == 0 and result.stdout.strip().lower() == "true"
        print(json.dumps({
            "installed": HERMES_BROKER.is_file(), "enabled": enabled,
            "server": str(HERMES_BROKER), "python": str(python),
        }))
        return
    if action == "remove":
        subprocess.run([hermes, "config", "unset", "mcp_servers.nbshell-ai-broker"], check=False)
        print("Hermes advisory broker removed. Restart Hermes to apply the change.")
        return
    if not HERMES_BROKER.is_file():
        raise SystemExit("Hermes broker is not installed. Run ./install.sh from the nbshell repository.")
    if not python.is_file():
        raise SystemExit("Hermes Python environment is unavailable.")
    if action == "test":
        subprocess.run([hermes, "mcp", "test", "nbshell-ai-broker"], check=True)
        return
    values = {
        "command": str(python),
        "args": json.dumps([str(HERMES_BROKER)]),
        "enabled": "true",
        "tools.include": json.dumps(HERMES_BROKER_TOOLS),
    }
    for suffix, value in values.items():
        subprocess.run([
            hermes, "config", "set", f"mcp_servers.nbshell-ai-broker.{suffix}", value,
        ], check=True)
    subprocess.run([hermes, "mcp", "test", "nbshell-ai-broker"], check=True)
    print("Hermes broker enabled. Restart Hermes to load advisory and transactional agent tools.")


def hermes_job_control(action: str, job_id: str, provider: str, repository: str,
                       task: str, yes: bool) -> None:
    if not HERMES_JOBS.is_file():
        raise SystemExit("Hermes transaction manager is not installed. Run ./install.sh.")
    command = [sys.executable, str(HERMES_JOBS), action]
    if action == "create":
        if not provider or not repository or not task:
            raise SystemExit("create requires --provider, --repository, and --task")
        command += [provider, repository, task]
    elif action == "list":
        if job_id: command += ["--job", job_id]
    elif action == "review":
        if not job_id or not provider: raise SystemExit("review requires job id and --provider")
        command += [job_id, provider]
    else:
        if not job_id: raise SystemExit(f"{action} requires a job id")
        command += [job_id]
        if yes: command.append("--yes")
    result = subprocess.run(command, check=False)
    if result.returncode:
        raise SystemExit(result.returncode)


def hermes_team_control(action: str, team_id: str, yes: bool) -> None:
    if not HERMES_TEAMS.is_file():
        raise SystemExit("Hermes supervised team manager is not installed. Run ./install.sh.")
    command = [sys.executable, str(HERMES_TEAMS), action]
    if action == "list":
        if team_id: command += ["--team", team_id]
    else:
        if not team_id: raise SystemExit(f"{action} requires a team id")
        command.append(team_id)
        if yes: command.append("--yes")
    result = subprocess.run(command, check=False)
    if result.returncode: raise SystemExit(result.returncode)


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
    print(f"HERDR    {len(state['sessions'])} session(s)")
    print(f"PROJECTS {len(state['projects'])} found")
    return problems


def skill_rows() -> list[dict]:
    home = Path.home()
    locations = (
        ("shared", home / ".agents/skills/nbshell", "OpenCode, Gemini, compatible agents"),
        ("claude", home / ".claude/skills/nbshell", "Claude Code /nbshell"),
        ("codex", home / ".codex/skills/nbshell", "Codex $nbshell"),
        ("pi", home / ".pi/agent/skills/nbshell", "Pi skills picker"),
    )
    source = SKILL_SOURCE.resolve()
    rows = []
    for agent_id, path, usage in locations:
        try:
            target = path.resolve(strict=True)
            ready = (target / "SKILL.md").is_file() and target == source
        except OSError:
            target = None
            ready = False
        rows.append({
            "id": agent_id,
            "ready": ready,
            "path": str(path),
            "target": str(target or ""),
            "usage": usage,
        })
    return rows


def skills_status(as_json: bool = False) -> int:
    rows = skill_rows()
    if as_json:
        print(json.dumps({"source": str(SKILL_SOURCE), "skills": rows}))
    else:
        print(f"NBSHELL SKILL  {SKILL_SOURCE}")
        for row in rows:
            mark = "ready" if row["ready"] else "missing"
            print(f"  {row['id']:<8} {mark:<8} {row['usage']}")
        if not all(row["ready"] for row in rows):
            print("\nRun ./install.sh from the nbshell repository to repair skill links.")
    return 0 if all(row["ready"] for row in rows) else 1


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
    skills = sub.add_parser("skills"); skills.add_argument("--json", action="store_true")
    default = sub.add_parser("default"); default.add_argument("agent", nargs="?")
    profile = sub.add_parser("profile"); profile.add_argument("profile", nargs="?", choices=["safe", "balanced", "autonomous"])
    model = sub.add_parser("model-profile"); model.add_argument("profile", nargs="?", choices=["local", "cloud", "private", "fast", "strong"])
    route_model = sub.add_parser("model"); route_model.add_argument("profile", choices=["local", "cloud", "private", "fast", "strong"]); route_model.add_argument("model")
    hermes_provider = sub.add_parser("hermes-provider"); hermes_provider.add_argument("provider", nargs="?", choices=sorted(HERMES_PROVIDERS))
    hermes_mode = sub.add_parser("hermes-mode"); hermes_mode.add_argument("mode", nargs="?", choices=sorted(HERMES_TOOLSETS))
    hermes_broker = sub.add_parser("hermes-broker"); hermes_broker.add_argument("action", nargs="?", default="status", choices=["status", "setup", "test", "remove"])
    hermes_job = sub.add_parser("hermes-job"); hermes_job.add_argument("action", choices=["create", "list", "review", "apply", "install", "push", "reject"]); hermes_job.add_argument("job_id", nargs="?", default=""); hermes_job.add_argument("--provider", choices=sorted(HERMES_PROVIDERS), default=""); hermes_job.add_argument("--repository", default=""); hermes_job.add_argument("--task", default=""); hermes_job.add_argument("--yes", action="store_true")
    hermes_team = sub.add_parser("hermes-team"); hermes_team.add_argument("action", choices=["list", "pause", "resume", "cancel", "apply", "install", "push", "reject"]); hermes_team.add_argument("team_id", nargs="?", default=""); hermes_team.add_argument("--yes", action="store_true")
    launch_p = sub.add_parser("launch"); launch_p.add_argument("agent", nargs="?"); launch_p.add_argument("--project"); launch_p.add_argument("--prompt", default=""); launch_p.add_argument("--resume", default="")
    quick_p = sub.add_parser("quick"); quick_p.add_argument("--project"); quick_p.add_argument("--prompt", default="")
    install_p = sub.add_parser("install"); install_p.add_argument("agent", choices=sorted(AGENTS))
    prompt_p = sub.add_parser("prompt"); prompt_p.add_argument("prompt", nargs="+"); prompt_p.add_argument("--agent"); prompt_p.add_argument("--project")
    ollama = sub.add_parser("ollama"); ollama.add_argument("action", nargs="?", default="status", choices=["status", "start", "stop"])
    workspace = sub.add_parser("workspace"); workspace.add_argument("template", choices=["dev", "review", "pair"]); workspace.add_argument("--project"); workspace.add_argument("--new-tab", action="store_true")
    session_focus = sub.add_parser("session-focus"); session_focus.add_argument("target")
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
        rows = herdr_sessions()
        if args.json: print(json.dumps(rows))
        else:
            for row in rows: print(f"{row['id']:<12} {row['name']:<10} {row['status']:<12} {row['project']}")
        return 0
    if command == "doctor": return doctor()
    if command == "skills": return skills_status(args.json)
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
    if command == "hermes-provider":
        if args.provider is None: print(config.get("hermesProvider", "codex")); return 0
        set_hermes_choice("provider", args.provider, HERMES_PROVIDERS); return 0
    if command == "hermes-mode":
        if args.mode is None: print(config.get("hermesMode", "restricted")); return 0
        set_hermes_choice("mode", args.mode, HERMES_TOOLSETS); return 0
    if command == "hermes-broker": hermes_broker_control(args.action); return 0
    if command == "hermes-job": hermes_job_control(args.action, args.job_id, args.provider, args.repository, args.task, args.yes); return 0
    if command == "hermes-team": hermes_team_control(args.action, args.team_id, args.yes); return 0
    if command == "launch": launch(args.agent, args.project, args.prompt, resume=args.resume); return 0
    if command == "quick": launch(None, args.project, args.prompt, quick=True); return 0
    if command == "install": install_agent(args.agent); return 0
    if command == "prompt": launch(args.agent, args.project, " ".join(args.prompt)); return 0
    if command == "ollama": ollama_control(args.action); return 0
    if command == "workspace": herdr_workspace(args.template, args.project, args.new_tab); return 0
    if command == "session-focus":
        herdr_result("agent", "focus", args.target.removeprefix("herdr:"))
        return 0
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.TimeoutExpired:
        raise SystemExit("Agent status request timed out.")
