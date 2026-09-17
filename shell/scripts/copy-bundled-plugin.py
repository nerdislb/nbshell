#!/usr/bin/env python3
"""Stage a bundled plugin without local development output.

This is packaging hygiene, not a sandbox or a secret scanner. The staged tree
must still pass the normal plugin and design validators before installation.
"""
import shutil
from pathlib import Path
import sys


def copy_plugin(source: Path, destination: Path):
    def ignore(directory, names):
        excluded = {".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
        if Path(directory) == source:
            excluded |= {"target", "node_modules", ".venv", "venv"}
        return set(names) & excluded
    # Preserve links for the validator to reject; never dereference them here.
    shutil.copytree(source, destination, symlinks=True, ignore=ignore)


if __name__ == "__main__":
    copy_plugin(Path(sys.argv[1]), Path(sys.argv[2]))
