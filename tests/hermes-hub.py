#!/usr/bin/env python3
"""Contract checks for the isolated Hermes provider hub."""

import importlib.util
import json
import tempfile
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("nbshell_agents", ROOT / "shell/scripts/agents.py")
assert SPEC and SPEC.loader
agents = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(agents)


def binary(name: str) -> str:
    paths = {"hermes": "/usr/bin/hermes", "agy": "/usr/bin/agy", "ghostty": "/usr/bin/ghostty"}
    return paths.get(name, "")


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    agents.CONFIG_DIR = root / "config"
    agents.CONFIG_FILE = agents.CONFIG_DIR / "agents.json"
    agents.HERMES_PILOT = root / "pilot"
    agents.HERMES_PILOT.mkdir()
    agents.antigravity_binary = lambda: "/usr/bin/agy"

    def launch_for(provider: str, mode: str, resume: str = "") -> str:
        config = agents.DEFAULT_CONFIG | {
            "hermesProvider": provider,
            "hermesMode": mode,
            "terminal": "ghostty",
        }
        agents.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        agents.CONFIG_FILE.write_text(json.dumps(config))
        with patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "Popen") as popen:
            agents.launch("hermes", None, resume=resume)
        return " ".join(popen.call_args.args[0])

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
    with patch.object(agents.Path, "home", return_value=root), patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "Popen") as popen:
        agents.launch("hermes", str(trusted_project))
    trusted = " ".join(popen.call_args.args[0])
    assert str(trusted_project) in trusted and "file,web,terminal,code_execution,todo,clarify,delegation,session_search,skills,nbshell-ai-broker" in trusted
    assert "--yolo" in trusted and str(agents.HERMES_PILOT) not in trusted
    assert popen.call_args.kwargs["cwd"] == trusted_project

    with patch.object(agents.Path, "home", return_value=root), patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "Popen") as popen:
        agents.launch("hermes", None)
    trusted_home = " ".join(popen.call_args.args[0])
    assert "--in " + str(root) in trusted_home and "--yolo" in trusted_home
    assert popen.call_args.kwargs["cwd"] == root

    trusted_config["hermesProvider"] = "gemini"; agents.CONFIG_FILE.write_text(json.dumps(trusted_config))
    with patch.object(agents.Path, "home", return_value=root), patch.object(agents.shutil, "which", side_effect=binary), patch.object(agents.subprocess, "Popen") as popen:
        agents.launch("hermes", str(trusted_project))
    trusted_gemini = " ".join(popen.call_args.args[0])
    assert "--dangerously-skip-permissions" in trusted_gemini and str(trusted_project) in trusted_gemini

    gemini = launch_for("gemini", "restricted")
    assert "/usr/bin/agy" in gemini and "--sandbox" in gemini and "plan" in gemini

print("Hermes hub contracts: OK")
