#!/usr/bin/env python3
"""Aggregate local Codex and Claude token metadata without reading prompts."""

from __future__ import annotations

import datetime as dt
import json
import os
from collections import defaultdict
from pathlib import Path


HOME = Path(os.environ.get("HOME", str(Path.home())))
TODAY = dt.datetime.now().astimezone().date()
CUTOFF = dt.datetime.now().timestamp() - 31 * 86400


def local_date(value: object, fallback: float) -> str:
    if isinstance(value, str) and value:
        try:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed.astimezone().date().isoformat()
        except ValueError:
            pass
    return dt.datetime.fromtimestamp(fallback).astimezone().date().isoformat()


def token_total(usage: object) -> int:
    if not isinstance(usage, dict):
        return 0
    explicit = usage.get("total_tokens")
    if isinstance(explicit, (int, float)):
        return max(0, int(explicit))
    return sum(max(0, int(usage.get(key, 0) or 0)) for key in (
        "input_tokens", "output_tokens", "cached_input_tokens",
        "cache_read_input_tokens", "cache_creation_input_tokens",
    ))


def files(root: Path):
    if not root.is_dir():
        return []
    return [path for path in root.rglob("*.jsonl") if path.is_file() and path.stat().st_mtime >= CUTOFF]


def empty_bucket():
    return defaultdict(int), defaultdict(int), 0


def codex_stats():
    days, models, sessions = empty_bucket()
    for path in files(Path(os.environ.get("CODEX_HOME", HOME / ".codex")) / "sessions"):
        latest_usage: dict = {}
        latest_model = "Codex"
        timestamp = None
        try:
            with path.open(errors="replace") as stream:
                for line in stream:
                    try:
                        row = json.loads(line)
                    except (json.JSONDecodeError, ValueError):
                        continue
                    timestamp = timestamp or row.get("timestamp")
                    payload = row.get("payload") or {}
                    if row.get("type") == "turn_context" and payload.get("model"):
                        latest_model = str(payload["model"])
                    if row.get("type") == "event_msg" and payload.get("type") == "token_count":
                        info = payload.get("info") or {}
                        candidate = info.get("total_token_usage") or info.get("last_token_usage") or {}
                        if isinstance(candidate, dict):
                            latest_usage = candidate
        except OSError:
            continue
        total = token_total(latest_usage)
        if total <= 0:
            continue
        day = local_date(timestamp, path.stat().st_mtime)
        days[day] += total
        models[latest_model] += total
        sessions += 1
    return result(days, models, sessions)


def claude_stats():
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR", HOME / ".claude"))
    days, models, sessions = empty_bucket()
    for path in files(config / "projects"):
        contributed = False
        try:
            with path.open(errors="replace") as stream:
                for line in stream:
                    try:
                        row = json.loads(line)
                    except (json.JSONDecodeError, ValueError):
                        continue
                    message = row.get("message") or {}
                    if row.get("type") != "assistant" or message.get("model") == "<synthetic>":
                        continue
                    total = token_total(message.get("usage") or {})
                    if total <= 0:
                        continue
                    day = local_date(row.get("timestamp"), path.stat().st_mtime)
                    days[day] += total
                    models[str(message.get("model") or "Claude")] += total
                    contributed = True
        except OSError:
            continue
        sessions += int(contributed)
    return result(days, models, sessions)


def result(days, models, sessions):
    recent = []
    for offset in range(6, -1, -1):
        date = TODAY - dt.timedelta(days=offset)
        recent.append({"date": date.isoformat(), "tokens": days[date.isoformat()]})
    model_rows = [
        {"name": name, "tokens": tokens}
        for name, tokens in sorted(models.items(), key=lambda item: (-item[1], item[0]))[:4]
    ]
    return {
        "recentDays": recent,
        "models": model_rows,
        "todayTokens": days[TODAY.isoformat()],
        "totalTokens": sum(days.values()),
        "sessions": sessions,
    }


def main():
    print(json.dumps({"codex": codex_stats(), "claude": claude_stats()}, separators=(",", ":")))


if __name__ == "__main__":
    main()
