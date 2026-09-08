#!/usr/bin/python3 -I
"""Explicit administrator setup, never callable through the theme action."""
import importlib.util
import os
from pathlib import Path
import sys


def main():
    if os.geteuid() != 0 or len(sys.argv) != 1:
        raise PermissionError("Run setup without arguments as administrator")
    source = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("brave_policy", source / "brave-theme-policy.py")
    policy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(policy)
    # All destination directories are checked and all leaves replaced atomically.
    # Validate/repair the legacy policy before granting the narrow color action.
    policy.publish("#1c2027")
    policy.atomic_file("/", ("usr", "lib", "nbshell"), "brave-theme-policy",
                       (source / "brave-theme-policy.py").read_bytes(), 0o755)
    policy.atomic_file("/", ("usr", "share", "polkit-1", "actions"), "org.nbshell.brave-theme.policy",
                       (source / "org.nbshell.brave-theme.policy").read_bytes())


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"nbshell Brave setup: {error}", file=sys.stderr)
        sys.exit(1)
