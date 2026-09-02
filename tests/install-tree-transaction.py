#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "install_tree_transaction",
    ROOT / "shell/scripts/install-tree-transaction.py",
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

with tempfile.TemporaryDirectory() as name:
    root = Path(name)
    prefix = root / "prefix"
    payload = root / "stage" / prefix.relative_to("/")
    payload.mkdir(parents=True)
    (payload / "bin").mkdir()
    (payload / "share/umbriel").mkdir(parents=True)
    (payload / "bin/umbriel").write_text("new compositor\n")
    (payload / "share/umbriel/portal").write_text("new portal\n")
    prefix.mkdir()
    (prefix / "bin").mkdir()
    (prefix / "share/umbriel").mkdir(parents=True)
    (prefix / "bin/umbriel").write_text("old compositor\n")
    (prefix / "share/umbriel/portal").write_text("old portal\n")

    try:
        MODULE.install_tree(root / "stage", prefix, fail_after=1)
    except RuntimeError as exc:
        assert "injected" in str(exc)
    else:
        raise AssertionError("failure injection unexpectedly succeeded")
    assert (prefix / "bin/umbriel").read_text() == "old compositor\n"
    assert (prefix / "share/umbriel/portal").read_text() == "old portal\n"
    assert not list(prefix.glob(".nbshell-umbriel-rollback-*"))

    MODULE.install_tree(root / "stage", prefix)
    assert (prefix / "bin/umbriel").read_text() == "new compositor\n"
    assert (prefix / "share/umbriel/portal").read_text() == "new portal\n"
    assert not list(prefix.glob(".nbshell-umbriel-rollback-*"))

with tempfile.TemporaryDirectory() as name:
    root = Path(name)
    prefix = root / "prefix"
    outside = root / "outside"
    payload = root / "stage" / prefix.relative_to("/")
    (payload / "linked").mkdir(parents=True)
    prefix.mkdir()
    outside.mkdir()
    (payload / "linked/escape.txt").write_text("escape\n")
    (prefix / "linked").symlink_to(outside, target_is_directory=True)

    try:
        MODULE.install_tree(root / "stage", prefix)
    except RuntimeError as exc:
        assert "symlinked destination parent" in str(exc)
    else:
        raise AssertionError("symlinked destination parent was accepted")

    assert (prefix / "linked").is_symlink()
    assert not (outside / "escape.txt").exists()

print("Umbriel install transaction tests: OK")
