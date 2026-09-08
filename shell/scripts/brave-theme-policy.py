#!/usr/bin/python3 -I
"""Publish only the nbshell Brave theme color; installed root-owned by setup."""
import json
import os
import re
import secrets
import sys


def checked_directory(root, parts):
    """Walk trusted directories by fd, never following a symlink."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open(root, flags)
    try:
        for part in (*parts, None):
            info = os.fstat(fd)
            if info.st_uid != os.geteuid() or info.st_mode & 0o022:
                raise PermissionError("Policy directories must be administrator-owned and not writable by others")
            if part is None:
                return fd
            try:
                os.mkdir(part, 0o755, dir_fd=fd)
            except FileExistsError:
                pass
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
    except BaseException:
        os.close(fd)
        raise


def atomic_file(root, parts, name, data, mode=0o644):
    fd = checked_directory(root, parts)
    temporary = ".nbshell-" + secrets.token_hex(16)
    created = False
    try:
        out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=fd)
        created = True
        with os.fdopen(out, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.fsync(stream.fileno())
        # Replacing the inode also revokes old writable file descriptors. A
        # legacy user-owned leaf or symlink is replaced, never followed.
        os.replace(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
        created = False
        os.fsync(fd)
    finally:
        if created:
            os.unlink(temporary, dir_fd=fd)
        os.close(fd)


def publish(color, root="/"):
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError("Expected exactly one #RRGGBB color")
    data = (json.dumps({"BrowserThemeColor": color}, separators=(",", ":")) + "\n").encode()
    atomic_file(root, ("etc", "brave", "policies", "managed"), "nbshell-color.json", data)


def main(argv):
    if len(argv) != 1:
        raise ValueError("Expected exactly one #RRGGBB color")
    if os.geteuid() != 0:
        raise PermissionError("Administrator authorization is required")
    publish(argv[0])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError) as error:
        print(f"nbshell Brave theme: {error}", file=sys.stderr)
        sys.exit(1)
