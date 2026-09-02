#!/usr/bin/env python3
"""Atomically overlay a DESTDIR tree onto its absolute installation paths."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import tempfile


def _leaves(stage: Path) -> list[Path]:
    leaves: list[Path] = []
    for root, directories, files in os.walk(stage, followlinks=False):
        base = Path(root)
        for name in list(directories):
            candidate = base / name
            if candidate.is_symlink():
                leaves.append(candidate)
                directories.remove(name)
        leaves.extend(base / name for name in files)
    return sorted(leaves, key=lambda path: path.relative_to(stage).as_posix())


def _copy_leaf(source: Path, destination: Path) -> None:
    temporary = destination.with_name(f".{destination.name}.nbshell-stage-{os.getpid()}")
    if temporary.exists() or temporary.is_symlink():
        temporary.unlink()
    try:
        if source.is_symlink():
            os.symlink(os.readlink(source), temporary)
        else:
            shutil.copy2(source, temporary, follow_symlinks=False)
        os.replace(temporary, destination)
    finally:
        if temporary.exists() or temporary.is_symlink():
            temporary.unlink()


def _reject_symlinked_parents(prefix: Path, relative: Path) -> None:
    current = prefix
    for part in relative.parts[:-1]:
        current = current / part
        if current.is_symlink():
            raise RuntimeError(f"refusing symlinked destination parent: {current}")
        if current.exists() and not current.is_dir():
            raise RuntimeError(f"destination parent is not a directory: {current}")


def install_tree(stage: Path, prefix: Path, *, fail_after: int | None = None) -> None:
    stage = stage.resolve()
    prefix = prefix.resolve()
    if not stage.is_dir() or not prefix.is_absolute():
        raise ValueError("stage directory and absolute prefix are required")

    relative_prefix = prefix.relative_to("/")
    payload = stage / relative_prefix
    if not payload.is_dir():
        raise ValueError(f"staged tree does not contain {prefix}")
    leaves = _leaves(payload)
    if not leaves:
        raise ValueError("staged install tree is empty")

    prefix.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix=".nbshell-umbriel-rollback-", dir=prefix))
    replaced: list[tuple[Path, Path | None]] = []
    created_directories: list[Path] = []
    try:
        for index, source in enumerate(leaves, start=1):
            relative = source.relative_to(payload)
            target = prefix / relative
            _reject_symlinked_parents(prefix, relative)
            parent = target.parent
            missing = []
            while parent != prefix and not parent.exists():
                missing.append(parent)
                parent = parent.parent
            for directory in reversed(missing):
                directory.mkdir()
                created_directories.append(directory)

            saved: Path | None = None
            if target.exists() or target.is_symlink():
                saved = backup / relative
                saved.parent.mkdir(parents=True, exist_ok=True)
                os.replace(target, saved)
            replaced.append((target, saved))
            _copy_leaf(source, target)
            if fail_after is not None and index >= fail_after:
                raise RuntimeError("injected Umbriel install failure")
    except BaseException:
        for target, saved in reversed(replaced):
            if target.exists() or target.is_symlink():
                target.unlink()
            if saved is not None:
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(saved, target)
        for directory in reversed(created_directories):
            try:
                directory.rmdir()
            except OSError:
                pass
        raise
    finally:
        shutil.rmtree(backup, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("prefix", type=Path)
    args = parser.parse_args()
    injected = os.environ.get("NBSHELL_UMBRIEL_INSTALL_FAIL_AFTER", "")
    fail_after = int(injected) if injected else None
    install_tree(args.stage, args.prefix, fail_after=fail_after)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
