#!/usr/bin/env python3
"""User-initiated attachment export through the desktop Save As dialog."""
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def suggested_name(filename, source):
    name = str(filename or source.name).replace("\\", "/").rsplit("/", 1)[-1]
    name = "".join(c for c in name if ord(c) >= 32 and ord(c) != 127).strip()
    return name if name not in ("", ".", "..") else "attachment"


def downloads_directory():
    try:
        result = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=3)
        candidate = Path(result.stdout.rstrip("\n"))
        if result.returncode == 0 and candidate.is_absolute() and candidate.is_dir():
            return candidate
    except (OSError, subprocess.TimeoutExpired):
        pass
    fallback = Path.home() / "Downloads"
    return fallback if fallback.is_dir() else Path.home()


def copy_atomic(source_fd, destination):
    destination = Path(destination)
    if not destination.is_absolute() or not destination.name:
        raise ValueError("Choose a local file destination.")
    if destination.is_symlink():
        raise ValueError("Choose a regular file, not a symbolic link.")
    if destination.exists():
        info = destination.stat()
        source = os.fstat(source_fd)
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("The destination is not a regular file.")
        if (source.st_dev, source.st_ino) == (info.st_dev, info.st_ino):
            raise ValueError("Choose a different location from the original attachment.")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".whatsapp-save-", delete=False) as output:
            temporary = Path(output.name)
            os.lseek(source_fd, 0, os.SEEK_SET)
            while chunk := os.read(source_fd, 1024 * 1024):
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def save(payload):
    source = Path(str(payload.get("path") or ""))
    if not source.is_absolute():
        raise ValueError("This attachment is not downloaded yet.")
    # Hold the actual regular file across the dialog, even if the cache changes.
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("This attachment is not a regular file.")
        suggested = downloads_directory() / suggested_name(payload.get("filename"), source)
        selected = subprocess.run([
            "/usr/bin/zenity", "--file-selection", "--save", "--confirm-overwrite",
            "--title=Save WhatsApp attachment", "--filename=" + str(suggested),
        ], capture_output=True, text=True)
        if selected.returncode == 1:
            return {"ok": True, "cancelled": True}
        if selected.returncode != 0:
            raise ValueError("The Save As dialog could not be opened.")
        # Zenity terminates its output with one newline; preserve spaces in names.
        destination = selected.stdout.removesuffix("\n")
        copy_atomic(fd, destination)
        return {"ok": True, "saved": True}
    finally:
        os.close(fd)


def main():
    try:
        payload = json.loads(sys.stdin.readline(16384))
        if not isinstance(payload, dict):
            raise ValueError("Invalid attachment request.")
        result = save(payload)
    except (OSError, ValueError) as error:
        message = error.strerror if isinstance(error, OSError) else str(error)
        print(json.dumps({"ok": False, "error": message or "The attachment could not be saved."}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
