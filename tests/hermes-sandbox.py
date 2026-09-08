#!/usr/bin/env python3
"""Adversarial checks of the real transaction namespace and its host boundary."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("jobs", ROOT / "resources/hermes-jobs/manager.py")
jobs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jobs)

with tempfile.TemporaryDirectory(prefix="nbshell-sandbox-test-") as temporary:
    root = Path(temporary)
    home = root / "home"; home.mkdir()
    repo = root / "workspace"; repo.mkdir()
    jobs.DATA_ROOT = root / "jobs"
    with patch.object(Path, "home", return_value=home):
        jobs._git(repo, "init", "-b", "main")
        (repo / "file").write_text("baseline\n")
        jobs._git(repo, "add", ".")
        jobs._git(repo, "commit", "-m", "baseline")
        command, _ = jobs._bwrap("test-job", repo, True, "codex")
        assert "--clearenv" in command
        assert command[command.index(str(repo / ".git")) - 1] == "--ro-bind"
        if not os.environ.get("CI"):
            attack = r'''
import os
from pathlib import Path
assert "NBSHELL_TEST_SENTINEL" not in os.environ
assert "GIT_CONFIG_COUNT" not in os.environ
assert os.environ["PATH"] == "/usr/bin"
for name in (".git/config", ".git/hooks/pre-commit", ".git/hooks/fsmonitor"):
    try:
        Path(name).write_text("not allowed")
    except OSError:
        pass
    else:
        raise AssertionError("metadata was writable: " + name)
try:
    Path(".git").rename(".git-away")
except OSError:
    pass
else:
    raise AssertionError("metadata mount could be replaced")
Path("file").write_text("agent result\n")
Path(".gitattributes").write_text("file filter=malicious\n")
'''
            env = dict(os.environ, NBSHELL_TEST_SENTINEL="synthetic-value", GIT_CONFIG_COUNT="1",
                       GIT_CONFIG_KEY_0="core.fsmonitor", GIT_CONFIG_VALUE_0="false")
            subprocess.run(command + ["/usr/bin/python3", "-c", attack], env=env, check=True)
        else:
            print("Real namespace probe skipped: CI does not permit user namespaces")
            (repo / "file").write_text("agent result\n")
            (repo / ".gitattributes").write_text("file filter=malicious\n")
        # Even project-selected filters must not import interactive Git config.
        marker = root / "outside"
        (home / ".gitconfig").write_text(
            f'[filter "malicious"]\nclean = "touch {marker}; cat"\n'
        )
        with patch.dict(os.environ, {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.fsmonitor",
                                     "GIT_CONFIG_VALUE_0": f"touch {marker}"}):
            jobs._git(repo, "add", "-A")
            jobs._git(repo, "commit", "-m", "collect result")
        assert not marker.exists()
        assert jobs._git(repo, "show", "HEAD:file").stdout == "agent result\n"

        # Human-approved source pushes retain trusted HTTPS credential helpers.
        helper = root / "credential-helper"
        helper.write_text("#!/bin/sh\nprintf 'username=fixture\npassword=synthetic\n'\n")
        helper.chmod(0o700)
        (home / ".gitconfig").write_text('[credential]\nhelper = ' + str(helper) + '\n')
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(home / '.config'), "NBSHELL_TEST_SENTINEL": "synthetic", "DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/fixture-bus", "XDG_RUNTIME_DIR": "/tmp/fixture-runtime"}):
            with patch.object(jobs.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as launch:
                jobs._host_push(repo, "main")
                env = launch.call_args.kwargs["env"]
            assert "NBSHELL_TEST_SENTINEL" not in env and "GIT_CONFIG_GLOBAL" not in env
            assert env["DBUS_SESSION_BUS_ADDRESS"] == "unix:path=/tmp/fixture-bus"
            assert "DBUS_SESSION_BUS_ADDRESS" not in jobs.process_environment()
            assert "XDG_RUNTIME_DIR" not in jobs.process_environment()
            credentials = subprocess.run(["/usr/bin/git", "credential", "fill"], input="protocol=https\nhost=fixture.invalid\n\n",
                                         env=env, text=True, capture_output=True, check=True)
            assert "username=fixture" in credentials.stdout and "password=synthetic" in credentials.stdout

legacy = {"id": "legacy-job", "repository": "/unused", "status": "reviewed",
          "commit": "abc", "reviews": [{"status": "approved"}]}
with patch.object(jobs, "_git", side_effect=AssertionError("must not inspect legacy metadata")):
    public = jobs.public_job(legacy, detail=True)
    assert not public["can_apply"] and not public["can_review"] and "diff" not in public
try:
    jobs.require_isolation(legacy)
except RuntimeError:
    pass
else:
    raise AssertionError("legacy workspace accepted")
print("Hermes Git metadata and environment boundary: OK")
