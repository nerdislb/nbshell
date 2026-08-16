#!/usr/bin/env python3
"""Kleiner, binärsicherer Bildverlauf für Clipboard.qml."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def paths(raw: str):
    root = Path(raw).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root, root / "index.json"


def load(index: Path):
    try:
        data = json.loads(index.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def save(index: Path, entries):
    fd, name = tempfile.mkstemp(prefix=".images.", dir=index.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(entries, handle, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, index)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def safe_file(root: Path, name: str):
    if not name or Path(name).name != name:
        raise SystemExit("ungültiger Bildname")
    candidate = (root / name).resolve()
    if candidate.parent != root or candidate.suffix != ".png":
        raise SystemExit("ungültiger Bildpfad")
    return candidate


def emit(entries):
    print(json.dumps(entries, ensure_ascii=False), flush=True)


def main():
    if len(sys.argv) < 3:
        raise SystemExit("Aufruf: clipboard-images.py capture|list|copy|remove|clear DIR [ARG]")
    command, raw_root = sys.argv[1:3]
    root, index = paths(raw_root)
    entries = load(index)

    if command == "list":
        emit([e for e in entries if safe_file(root, str(e.get("file", ""))).is_file()])
        return
    if command == "capture":
        data = sys.stdin.buffer.read()
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            return
        digest = hashlib.sha256(data).hexdigest()
        name = digest + ".png"
        destination = safe_file(root, name)
        if not destination.exists():
            fd, temporary = tempfile.mkstemp(prefix=".image.", dir=root)
            try:
                with os.fdopen(fd, "wb") as handle:
                    handle.write(data)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary, destination)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        keep = max(1, min(100, int(sys.argv[3]) if len(sys.argv) > 3 else 20))
        entries = [{"file": name, "sha256": digest}] + [e for e in entries if e.get("file") != name]
        removed, entries = entries[keep:], entries[:keep]
        for entry in removed:
            safe_file(root, str(entry.get("file", ""))).unlink(missing_ok=True)
        save(index, entries)
        emit(entries)
        return
    if command == "copy":
        image = safe_file(root, sys.argv[3])
        subprocess.run(["wl-copy", "--type", "image/png"], input=image.read_bytes(), check=True)
        return
    if command == "remove":
        name = sys.argv[3]
        safe_file(root, name).unlink(missing_ok=True)
        entries = [e for e in entries if e.get("file") != name]
        save(index, entries)
        emit(entries)
        return
    if command == "clear":
        for entry in entries:
            safe_file(root, str(entry.get("file", ""))).unlink(missing_ok=True)
        save(index, [])
        emit([])
        return
    raise SystemExit("unbekannter Befehl")


if __name__ == "__main__":
    main()
