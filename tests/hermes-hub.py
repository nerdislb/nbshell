#!/usr/bin/env python3
"""Contract checks for the isolated Hermes provider hub."""

import importlib.util
import json
import sqlite3
import tempfile
import time
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("nbshell_agents", ROOT / "shell/scripts/agents.py")
assert SPEC and SPEC.loader
agents = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(agents)


def binary(name: str) -> str:
    paths = {
        "hermes": "/usr/bin/hermes", "agy": "/usr/bin/agy",
        "ghostty": "/usr/bin/ghostty", "systemd-run": "/usr/bin/systemd-run",
    }
    return paths.get(name, "")


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    agents.CONFIG_DIR = root / "config"
    agents.CONFIG_FILE = agents.CONFIG_DIR / "agents.json"
    agents.HERMES_PILOT = root / "pilot"
    agents.HERMES_PILOT.mkdir()
    agents.antigravity_binary = lambda: "/usr/bin/agy"

    hermes_home = root / "hermes"
    hermes_home.mkdir()
    database = sqlite3.connect(hermes_home / "state.db")
    database.execute("""CREATE TABLE sessions (
        id TEXT, source TEXT, model TEXT, started_at REAL, last_activity_at REAL,
        ended_at REAL, message_count INTEGER, tool_call_count INTEGER,
        input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER,
        cache_write_tokens INTEGER, reasoning_tokens INTEGER, api_call_count INTEGER,
        actual_cost_usd REAL, estimated_cost_usd REAL, cost_status TEXT, title TEXT,
        cwd TEXT, last_activity_description TEXT, archived INTEGER, hidden INTEGER
    )""")
    database.execute("""INSERT INTO sessions VALUES
        ('home-session', 'tui', 'test-model', ?, ?, NULL, 4, 2, 100, 20,
         300, 10, 5, 2, NULL, 0.25, 'estimated', 'Active work', ?,
         'tool running: terminal', 0, 0)""", (time.time() - 30, time.time(), str(root)))
    database.execute("""INSERT INTO sessions VALUES
        ('broker-session', 'cli', 'review-model', ?, ?, ?, 2, 0, 10, 5,
         0, 0, 0, 1, NULL, 0.10, 'estimated', 'Review', ?, '', 0, 0)""",
        (time.time() - 20, time.time(), time.time(), str(root / "broker")))
    database.commit(); database.close()

    sessions = agents.hermes_sessions(hermes_home)
    assert len(sessions) == 1 and sessions[0]["id"] == "home-session"
    assert sessions[0]["active"] and sessions[0]["cacheReadTokens"] == 300
    usage = agents.hermes_usage(hermes_home)["today"]
    assert usage["sessions"] == 2 and usage["inputTokens"] == 110
    assert usage["cacheTokens"] == 310 and usage["costUsd"] == 0.35

    def launch_for(provider: str, mode: str, resume: str = "") -> str:
        config = agents.DEFAULT_CONFIG | {
            "hermesProvider": provider,
            "hermesMode": mode,
            "terminal": "ghostty",
        }
        agents.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        agents.CONFIG_FILE.write_text(json.dumps(config))
        with patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "run") as run, patch.object(agents.subprocess, "Popen") as popen:
            run.return_value.returncode = 0
            agents.launch("hermes", None, resume=resume)
        launched = popen.call_args.args[0]
        assert launched[:6] == [
            "systemd-run", "--user", "--scope", "--quiet", "--collect",
            "--slice=app.slice",
        ]
        assert launched[6].startswith("--unit=nbshell-agent-hermes-")
        assert launched[7] == "--"
        return " ".join(launched)

    codex = launch_for("codex", "restricted")
    assert "--provider" in codex and "openai-codex" in codex
    assert "--toolsets" in codex and "file,nbshell-ai-broker" in codex
    assert "--yolo" not in codex

    claude = launch_for("claude", "research", "session-1")
    assert "anthropic" in claude and "anthropic/claude-sonnet-4.6" in claude
    assert "file,web,nbshell-ai-broker" in claude and "--resume" in claude and "session-1" in claude

    workspace = launch_for("codex", "workspace")
    assert "file,web,terminal,nbshell-ai-broker" in workspace
    assert "--yolo" not in workspace

    trusted_project = root / "AndroidStudioProjects" / "nbos"
    trusted_project.mkdir(parents=True); (trusted_project / ".git").mkdir()
    trusted_config = agents.DEFAULT_CONFIG | {
        "hermesProvider": "codex", "hermesMode": "trusted", "terminal": "ghostty",
        "lastProject": str(trusted_project),
    }
    agents.CONFIG_FILE.write_text(json.dumps(trusted_config))
    with patch.object(agents.Path, "home", return_value=root), patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "run") as run, patch.object(agents.subprocess, "Popen") as popen:
        run.return_value.returncode = 0
        agents.launch("hermes", str(trusted_project))
    trusted = " ".join(popen.call_args.args[0])
    assert str(trusted_project) in trusted and "file,web,terminal,code_execution,todo,clarify,delegation,session_search,skills,nbshell-ai-broker" in trusted
    assert "--yolo" in trusted and str(agents.HERMES_PILOT) not in trusted
    assert popen.call_args.kwargs["cwd"] == trusted_project
    assert popen.call_args.kwargs["env"]["TERMINAL_CWD"] == str(trusted_project)
    run.assert_called_once()
    assert run.call_args.args[0][-2:] == ["terminal.cwd", str(trusted_project)]

    with patch.object(agents.Path, "home", return_value=root), patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "run") as run, patch.object(agents.subprocess, "Popen") as popen:
        run.return_value.returncode = 0
        agents.launch("hermes", None)
    trusted_home = " ".join(popen.call_args.args[0])
    assert "--in " + str(root) in trusted_home and "--yolo" in trusted_home
    assert popen.call_args.kwargs["cwd"] == root

    trusted_config["hermesProvider"] = "gemini"; agents.CONFIG_FILE.write_text(json.dumps(trusted_config))
    with patch.object(agents.Path, "home", return_value=root), patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "run") as run, patch.object(agents.subprocess, "Popen") as popen:
        run.return_value.returncode = 0
        agents.launch("hermes", str(trusted_project))
    trusted_gemini = " ".join(popen.call_args.args[0])
    assert "--dangerously-skip-permissions" in trusted_gemini and str(trusted_project) in trusted_gemini

    gemini = launch_for("gemini", "restricted")
    assert "/usr/bin/agy" in gemini and "--sandbox" in gemini and "plan" in gemini

    existing = json.dumps([
        {"id": "ordinary", "app_id": "org.example.Terminal", "active": True},
        {"id": "hermes-window", "app_id": "dev.nerdi.nbshell.agent.hermes", "active": True},
    ])
    windows_result = type("Result", (), {"returncode": 0, "stdout": existing})()
    focus_result = type("Result", (), {"returncode": 0, "stdout": ""})()
    with patch.object(agents.shutil, "which", return_value="/usr/bin/umbriel"), \
         patch.object(agents.subprocess, "run", side_effect=[windows_result, focus_result]) as run, \
         patch.object(agents, "launch") as launch:
        agents.open_hermes_session("home-session")
    assert run.call_args_list[-1].args[0] == ["umbriel", "msg", "window-focus-warp:hermes-window"]
    launch.assert_not_called()

    no_windows = type("Result", (), {"returncode": 0, "stdout": "[]"})()
    with patch.object(agents.shutil, "which", return_value="/usr/bin/umbriel"), \
         patch.object(agents.subprocess, "run", return_value=no_windows), \
         patch.object(agents, "launch") as launch:
        agents.open_hermes_session("home-session")
    launch.assert_called_once_with("hermes", None, resume="home-session")

    agent_center = (ROOT / "shell/Menu/AgentCenter.qml").read_text()
    assert 'Agents.openHermes(hermesOverview.current.id || "")' in agent_center
    assert 'Agents.launch("hermes", "")' not in agent_center
    assert agent_center.index("root.close();", agent_center.index("id: openHermes")) < agent_center.index(
        'Agents.openHermes(hermesOverview.current.id || "")', agent_center.index("id: openHermes")
    )

print("Hermes hub contracts: OK")
