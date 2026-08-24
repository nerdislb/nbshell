#!/usr/bin/env python3
import importlib.util
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("umbriel_update", ROOT / "shell/scripts/umbriel-update.py")
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)

assert UPDATE.canonical_remote("git@github.com:noctalia-dev/umbriel.git") == \
    "https://github.com/noctalia-dev/umbriel"
assert UPDATE.canonical_remote("https://github.com/noctalia-dev/umbriel.git") == \
    "https://github.com/noctalia-dev/umbriel"


def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True)


with tempfile.TemporaryDirectory() as name:
    source_root = pathlib.Path(name)
    for project, remote in UPDATE.PROJECTS:
        checkout = source_root / project
        checkout.mkdir()
        run("git", "init", "-q", cwd=checkout)
        run("git", "config", "user.email", "test@nbshell.local", cwd=checkout)
        run("git", "config", "user.name", "nbshell test", cwd=checkout)
        (checkout / "README").write_text("fixture\n")
        run("git", "add", "README", cwd=checkout)
        run("git", "commit", "-qm", "fixture", cwd=checkout)
        run("git", "remote", "add", "origin", remote, cwd=checkout)

    os.environ["NBSHELL_UMBRIEL_SOURCE_DIR"] = str(source_root)
    clean = UPDATE.status(fetch=False)
    assert clean["ok"] and clean["installed"] and clean["installable"]
    assert not clean["available"]

    (source_root / "umbriel" / "README").write_text("local change\n")
    dirty = UPDATE.status(fetch=False)
    assert not dirty["installable"]
    assert "local changes" in dirty["error"]

print("Umbriel updater tests: OK")
