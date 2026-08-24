#!/usr/bin/env python3
import importlib.util
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("agents", ROOT / "shell/scripts/agents.py")
AGENTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGENTS)

with tempfile.TemporaryDirectory() as name:
    temp = pathlib.Path(name)
    AGENTS.STATE_DIR = temp / "state"
    AGENTS.CONFIG_DIR = temp / "config"
    AGENTS.NATIVE_FILE = AGENTS.STATE_DIR / "agent-sessions.json"
    AGENTS.CONFIG_FILE = AGENTS.CONFIG_DIR / "agents.json"
    calls = []

    def fake_tmux(*args, input_text=None, timeout=5, check=True):
        calls.append((args, input_text))
        code = 1 if args[:2] == ("has-session", "-t") else 0
        return subprocess.CompletedProcess(args, code, "", "")

    real_tmux = AGENTS.tmux
    real_which = AGENTS.shutil.which
    real_ensure_host = AGENTS.ensure_native_host
    AGENTS.tmux = fake_tmux
    AGENTS.shutil.which = lambda binary: "/usr/bin/" + binary
    AGENTS.ensure_native_host = lambda: False
    try:
        AGENTS.native_start("codex", str(temp), "")
        state = AGENTS.load_native_state()
        assert len(state["sessions"]) == 1
        session = state["sessions"][0]
        assert session["agent"] == "codex" and session["project"] == str(temp)
        assert any(call[0][0] == "new-session" for call in calls)
        assert session["statusMode"] == "hook"
        target = "nbshell:" + session["name"]
        AGENTS.native_prompt(target, "Review this safely")
        assert any(call[0][0] == "load-buffer" and call[1] == "Review this safely" for call in calls)
        assert any(call[0][0] == "send-keys" and call[0][-1] == "Enter" for call in calls)
        assert AGENTS.load_native_state()["sessions"][0]["status"] == "working"
        AGENTS.native_event(target, "finished")
        assert AGENTS.load_native_state()["sessions"][0]["status"] == "done"
    finally:
        AGENTS.tmux = real_tmux
        AGENTS.shutil.which = real_which
        AGENTS.ensure_native_host = real_ensure_host

print("Native agent session tests: OK")
