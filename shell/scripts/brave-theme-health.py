#!/usr/bin/env python3
"""Read-only metadata check; never prints policy contents or host-specific paths."""
from pathlib import Path
import stat


def status(path=Path('/etc/brave/policies/managed/nbshell-color.json'), owner=0, root=Path("/")):
    try:
        leaf = path.lstat()
    except FileNotFoundError:
        return 'absent'
    except OSError:
        return 'unknown'
    try:
        if not stat.S_ISREG(leaf.st_mode) or leaf.st_uid != owner or leaf.st_mode & 0o022:
            return 'insecure'
        if not path.is_relative_to(root):
            return 'unknown'
        for parent in path.parents:
            info = parent.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != owner or info.st_mode & 0o022:
                return 'insecure'
            if parent == root:
                break
    except OSError:
        return 'unknown'
    return 'secure'


if __name__ == '__main__': print(status())
