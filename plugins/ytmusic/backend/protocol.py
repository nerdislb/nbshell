"""Newline-delimited JSON protocol for the YouTube Music backend."""

from __future__ import annotations

import json
from typing import Any

PROTOCOL_VERSION = 1
BACKEND_VERSION = "1.1.1"
# One NDJSON frame. Catalog payloads stay well under this; a missing newline
# must not grow the Omarchy shell SplitParser buffer without bound.
MAX_LINE_BYTES = 256 * 1024

ERROR_UNSUPPORTED_VERSION = "unsupported_version"
ERROR_UNKNOWN_COMMAND = "unknown_command"
ERROR_INVALID_REQUEST = "invalid_request"
ERROR_AUTH = "auth_failed"
ERROR_UNAVAILABLE = "unavailable"
ERROR_PLAYBACK = "playback_failed"
ERROR_CATALOG = "catalog_failed"


def dumps(payload: dict[str, Any]) -> str:
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=False)


def line_size(text: str | bytes) -> int:
    if isinstance(text, bytes):
        return len(text)
    return len(str(text or "").encode("utf-8"))


def parse_line(line: str, max_bytes: int = MAX_LINE_BYTES) -> dict[str, Any] | None:
    text = (line or "").strip()
    if not text:
        return None
    if line_size(text) > max_bytes:
        return None
    try:
        message = json.loads(text)
    except json.JSONDecodeError:
        return None
    return message if isinstance(message, dict) else None


def _stripped_payload(payload: dict[str, Any]) -> dict[str, Any]:
    next_payload = dict(payload)
    if next_payload.get("type") == "event" and isinstance(next_payload.get("state"), dict):
        state = dict(next_payload["state"])
        state["play_history"] = []
        track = state.get("track")
        state["queue"] = [track] if isinstance(track, dict) else []
        next_payload["state"] = state
        return next_payload
    if next_payload.get("type") == "response" and isinstance(next_payload.get("result"), dict):
        result = dict(next_payload["result"])
        for key in ("home", "items", "sections", "play_history", "queue"):
            if key in result:
                result[key] = []
        next_payload["result"] = result
    return next_payload


def encode_line(payload: dict[str, Any], max_bytes: int = MAX_LINE_BYTES) -> bytes:
    data = (dumps(payload) + "\n").encode("utf-8")
    if len(data) <= max_bytes:
        return data
    slim = _stripped_payload(payload)
    data = (dumps(slim) + "\n").encode("utf-8")
    if len(data) <= max_bytes:
        return data
    fallback = response(
        payload.get("id"), False,
        code=ERROR_UNAVAILABLE,
        message="Response too large",
    )
    return (dumps(fallback) + "\n").encode("utf-8")


def response(request_id: Any, ok: bool, result: dict[str, Any] | None = None,
             code: str = "", message: str = "") -> dict[str, Any]:
    payload: dict[str, Any] = {
        "type": "response",
        "v": PROTOCOL_VERSION,
        "id": request_id,
        "ok": ok,
    }
    if ok:
        payload["result"] = result or {}
    else:
        payload["error"] = {
            "code": code or ERROR_INVALID_REQUEST,
            "message": redact(message or "Request failed"),
        }
    return payload


def event(name: str, state: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "event",
        "v": PROTOCOL_VERSION,
        "event": name,
        "state": state,
    }


def redact(value: str) -> str:
    text = str(value or "")
    replacements = (
        ("authorization", True),
        ("cookie", True),
        ("sapisid", True),
        ("access_token", False),
        ("refresh_token", False),
    )
    lower = text.lower()
    for token, headerish in replacements:
        if token not in lower:
            continue
        # Keep the surrounding message; drop the secret itself.
        text = _redact_token(text, token, headerish)
    return text


def _redact_token(text: str, token: str, headerish: bool) -> str:
    import re

    if headerish:
        pattern = re.compile(rf"({token}\s*[:=]\s*)([^\s;]+)", re.IGNORECASE)
        return pattern.sub(r"\1<redacted>", text)
    pattern = re.compile(rf"({token}=)[^&\s]+", re.IGNORECASE)
    return pattern.sub(r"\1<redacted>", text)
