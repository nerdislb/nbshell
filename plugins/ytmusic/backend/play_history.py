"""Local play history for the YouTube Music plugin."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import auth
from catalog import watch_url

MAX_ITEMS = 80


def history_path() -> Path:
    return auth.config_dir() / "play-history.json"


def video_id(item: dict | None) -> str:
    source = item or {}
    return str(source.get("videoId") or source.get("id") or "").strip()


def load(path: Path | None = None) -> list[dict[str, Any]]:
    target = path or history_path()
    try:
        raw = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return []
    if not isinstance(raw, list):
        return []
    return [row for row in raw if isinstance(row, dict) and video_id(row)][:MAX_ITEMS]


def save(rows: list[dict[str, Any]], path: Path | None = None) -> None:
    target = path or history_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = [row for row in rows if isinstance(row, dict) and video_id(row)][:MAX_ITEMS]
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        target.chmod(0o600)
    except OSError:
        pass


def remember(item: dict | None, existing: list[dict[str, Any]] | None = None,
             path: Path | None = None) -> list[dict[str, Any]]:
    track = dict(item or {})
    vid = video_id(track)
    if not vid:
        return list(existing) if existing is not None else load(path)
    rows = [row for row in (existing if existing is not None else load(path))
            if video_id(row) != vid]
    track["videoId"] = vid
    if not str(track.get("externalUrl") or "").strip():
        track["externalUrl"] = watch_url(vid)
    rows.insert(0, track)
    rows = rows[:MAX_ITEMS]
    save(rows, path)
    return rows


def merge(local: list[dict[str, Any]] | None,
          remote: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for row in list(local or []) + list(remote or []):
        if not isinstance(row, dict):
            continue
        vid = video_id(row)
        if not vid or vid in seen:
            continue
        seen.add(vid)
        out.append(row)
        if len(out) >= MAX_ITEMS:
            break
    return out
