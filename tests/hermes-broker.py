#!/usr/bin/env python3
"""Static safety contracts for the optional Hermes advisory broker."""

import ast
import tempfile
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "resources/hermes-broker/server.py").read_text()
tree = ast.parse(source)

assert "ask_codex" in source and "ask_claude" in source and "ask_gemini" in source
assert "start_codex_job" in source and "start_claude_job" in source and "start_gemini_job" in source
assert "review_agent_job" in source and "agent_job_status" in source
assert "start_supervised_team" in source and "supervised_team_status" in source
assert "prepare_brain_proposal" in source and "revise_brain_proposal" in source and "brain_proposal_status" in source
assert "transaction repositories must be under" in source
assert "shell=True" not in source
assert "--dangerously" not in source and "--yolo" not in source
assert "--ignore-user-config" in source and "--ignore-rules" in source
assert "--die-with-parent" in source and "--ro-bind" in source
assert "RATE_LIMIT = 6" in source and "TIMEOUT_SECONDS = 120" in source
assert "request_chars" in source and '"question"' not in source[source.index("def _audit"):source.index("def _run_provider")]
assert any(isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "run" for node in ast.walk(tree))
assert '"apply"' not in source[source.index("JOB_TOOLS"):source.index("async def _advice")]

# Exercise the real path guard without importing MCP/provider dependencies.
guard = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "_broker_repository")
namespace = {"Path": Path, "_safe_text": lambda value, label: str(value)}
exec(compile(ast.Module(body=[guard], type_ignores=[]), str(ROOT / "resources/hermes-broker/server.py"), "exec"), namespace)
with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary).resolve()
    home = base / "home"
    home.mkdir()
    outside = base / "home-other"
    outside.mkdir()
    (home / "escape").symlink_to(outside, target_is_directory=True)
    with patch.object(Path, "home", return_value=home):
        for relative in ("projects/app", "AndroidStudioProjects/nbos", "Sync/brain", ".config/example"):
            target = home / relative
            assert namespace["_broker_repository"](str(target)) == str(target)
        for target in (outside, home / ".." / "home-other", home / "escape" / "repo", Path("/etc")):
            try:
                namespace["_broker_repository"](str(target))
            except ValueError:
                pass
            else:
                raise AssertionError(f"Accepted repository outside Home: {target}")

print("Hermes broker safety contracts: OK")

# A slow transaction manager must not stall unrelated MCP work.
import asyncio
import json
import os
import time
from types import SimpleNamespace
nodes = []
for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in ('call_tool', '_base_env'):
        node.decorator_list = []
        nodes.append(node)
namespace = {
    'Path': Path, 'os': os, 'asyncio': asyncio, 'json': json, 'JOB_TOOLS': {},
    '_safe_text': lambda value, label: str(value),
    'types': SimpleNamespace(CallToolResult=lambda **kw: SimpleNamespace(**kw), TextContent=lambda **kw: SimpleNamespace(**kw)),
}
exec(compile(ast.Module(body=nodes, type_ignores=[]), '<broker-functions>', 'exec'), namespace)
with patch.dict(os.environ, {'NBSHELL_TEST_SECRET': 'sentinel', 'XDG_STATE_HOME': '/tmp/fixture-state'}):
    assert 'NBSHELL_TEST_SECRET' not in namespace['_base_env']()
    assert namespace['_base_env']()['XDG_STATE_HOME'] == '/tmp/fixture-state'

def slow_manager(*args):
    time.sleep(0.3)
    return {'status': 'ready'}
namespace['_job_command'] = slow_manager

async def responsive():
    began = time.monotonic()
    request = asyncio.create_task(namespace['call_tool'](None, SimpleNamespace(name='agent_job_status', arguments={'job_id': 'fixture'})))
    await asyncio.sleep(0.03)
    assert time.monotonic() - began < 0.2, 'MCP event loop was blocked by transaction command'
    result = await request
    assert json.loads(result.content[0].text)['status'] == 'ready'
asyncio.run(responsive())
print('Hermes broker environment and asynchronous responsiveness: OK')

# Gemini uses namespace-local paths even when host XDG roots differ.
import shutil
import subprocess
node = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == '_gemini_command')
namespace['shutil'] = shutil
exec(compile(ast.Module(body=[node], type_ignores=[]), '<gemini-command>', 'exec'), namespace)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    home = root / 'home'; home.mkdir()
    agy = home / '.local/share/antigravity/bin/agy'
    agy.parent.mkdir(parents=True); agy.write_text('fixture')
    cli = home / '.gemini/antigravity-cli'; cli.mkdir(parents=True)
    for name in ('antigravity-oauth-token', 'settings.json', 'installation_id', 'jetski_state.pbtxt'):
        (cli / name).write_text('{}')
    broker = root / 'broker'; broker.mkdir()
    namespace['BROKER_HOME'] = broker
    with patch.object(Path, 'home', return_value=home):
        command, _ = namespace['_gemini_command']('fixture')
    assert '--clearenv' in command and '--unshare-all' in command
    prefix = command[:command.index(str(agy))]
    if not os.environ.get('CI'):
        probe = 'import os; from pathlib import Path; assert "NBSHELL_TEST_SECRET" not in os.environ; assert "DBUS_SESSION_BUS_ADDRESS" not in os.environ; assert os.environ["XDG_DATA_HOME"] == os.environ["HOME"] + "/.local/share"; assert Path(os.environ["XDG_CACHE_HOME"]).is_dir(); assert not Path("/proc/' + str(os.getpid()) + '").exists()'
        env = dict(os.environ, NBSHELL_TEST_SECRET='synthetic', XDG_DATA_HOME='/unmounted/host-data', DBUS_SESSION_BUS_ADDRESS='unix:path=/tmp/fixture-bus')
        subprocess.run(prefix + ['/usr/bin/python3', '-c', probe], env=env, check=True)
print('Gemini broker real namespace and private XDG environment: OK')
