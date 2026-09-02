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

updates_qml = (ROOT / "shell/Services/ShellUpdates.qml").read_text()
assert updates_qml.count("' install --yes;") == 2


def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True)


with tempfile.TemporaryDirectory() as name:
    source_root = pathlib.Path(name)
    remotes = source_root / "remotes"
    seeds = source_root / "seeds"
    remotes.mkdir()
    seeds.mkdir()
    projects = []
    initial = {}
    for project, _remote in UPDATE.PROJECTS:
        remote = remotes / f"{project}.git"
        seed = seeds / project
        run("git", "init", "-q", "--bare", str(remote), cwd=source_root)
        run("git", "init", "-q", "-b", "main", str(seed), cwd=source_root)
        run("git", "config", "user.email", "test@nbshell.local", cwd=seed)
        run("git", "config", "user.name", "nbshell test", cwd=seed)
        (seed / "README").write_text("fixture\n")
        run("git", "add", "README", cwd=seed)
        run("git", "commit", "-qm", "fixture", cwd=seed)
        run("git", "remote", "add", "origin", str(remote), cwd=seed)
        run("git", "push", "-qu", "origin", "main", cwd=seed)
        run("git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main", cwd=source_root)
        run("git", "clone", "-q", str(remote), str(source_root / project), cwd=source_root)
        initial[project] = subprocess.check_output(
            ["git", "-C", str(seed), "rev-parse", "HEAD"], text=True,
        ).strip()
        projects.append((project, str(remote)))

    os.environ["NBSHELL_UMBRIEL_SOURCE_DIR"] = str(source_root)
    setattr(UPDATE, "PROJECTS", tuple(projects))
    clean = UPDATE.status(fetch=False)
    assert clean["ok"] and clean["installed"] and clean["installable"]
    assert not clean["available"]

    umbriel_seed = seeds / "umbriel"
    (umbriel_seed / "README").write_text("upstream change\n")
    run("git", "add", "README", cwd=umbriel_seed)
    run("git", "commit", "-qm", "upstream change", cwd=umbriel_seed)
    run("git", "push", "-q", "origin", "main", cwd=umbriel_seed)
    latest = subprocess.check_output(
        ["git", "-C", str(umbriel_seed), "rev-parse", "HEAD"], text=True,
    ).strip()

    online = UPDATE.status(fetch=True)
    assert online["ok"] and online["available"] and online["installable"]
    assert online["projects"]["umbriel"]["current"] == initial["umbriel"][:8]
    assert online["projects"]["umbriel"]["latest"] == latest[:8]
    assert online["projects"]["umbriel"]["target"] == latest
    assert online["projects"]["umbriel"]["available"]
    assert not online["projects"]["xdg-desktop-portal-umbriel"]["available"]

    (source_root / "umbriel" / "README").write_text("local change\n")
    blocked = UPDATE.status(fetch=True)
    assert blocked["available"] and not blocked["installable"]
    assert "Local source changes block this update" in blocked["blockedReason"]
    assert "umbriel: README" in blocked["blockedReason"], blocked
    assert blocked["error"] == ""
    run("git", "checkout", "--", "README", cwd=source_root / "umbriel")

    prepared = source_root / "prepared-umbriel"
    UPDATE.prepare_worktree(
        source_root / "umbriel", str(remotes / "umbriel.git"),
        online["projects"]["umbriel"]["target"], prepared,
    )
    checked_out = subprocess.check_output(
        ["git", "-C", str(prepared), "rev-parse", "HEAD"], text=True,
    ).strip()
    assert checked_out == latest
    assert subprocess.check_output(
        ["git", "-C", str(source_root / "umbriel"), "rev-parse", "HEAD"], text=True,
    ).strip() == initial["umbriel"]
    run("git", "worktree", "remove", "--force", str(prepared), cwd=source_root / "umbriel")
    UPDATE.advance_checkout(source_root / "umbriel", str(remotes / "umbriel.git"), latest)
    assert subprocess.check_output(
        ["git", "-C", str(source_root / "umbriel"), "rev-parse", "HEAD"], text=True,
    ).strip() == latest
    try:
        UPDATE.prepare_worktree(
            source_root / "umbriel", str(remotes / "umbriel.git"),
            "main", source_root / "invalid-target",
        )
    except RuntimeError as exc:
        assert "invalid target revision" in str(exc)
    else:
        raise AssertionError("invalid update target was accepted")

    run("git", "checkout", "--orphan", "replacement", cwd=umbriel_seed)
    (umbriel_seed / "README").write_text("replacement history\n")
    run("git", "add", "README", cwd=umbriel_seed)
    run("git", "commit", "-qm", "replacement history", cwd=umbriel_seed)
    run("git", "push", "-qf", "origin", "HEAD:main", cwd=umbriel_seed)
    divergent = UPDATE.status(fetch=True)
    assert not divergent["ok"] and not divergent["available"] and not divergent["installable"]
    assert "does not fast-forward" in divergent["error"]

    (source_root / "umbriel" / "README").write_text("local change\n")
    dirty = UPDATE.status(fetch=False)
    assert not dirty["installable"]
    assert dirty["blockedReason"] == ""
    assert dirty["error"] == ""

    run("git", "checkout", "--", "README", cwd=source_root / "umbriel")

print("Umbriel updater tests: OK")
