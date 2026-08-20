"""Newline-delimited JSON protocol for the Omarchy YouTube Music backend."""

from __future__ import annotations

import json
from typing import Any

PROTOCOL_VERSION = 1
BACKEND_VERSION = "1.1.0"

ERROR_UNSUPPORTED_VERSION = "unsupported_version"
ERROR_UNKNOWN_COMMAND = "unknown_command"
ERROR_INVALID_REQUEST = "invalid_request"
ERROR_AUTH = "auth_failed"
ERROR_UNAVAILABLE = "unavailable"
ERROR_PLAYBACK = "playback_failed"
ERROR_CATALOG = "catalog_failed"


def dumps(payload: dict[str, Any]) -> str:
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=False)


def parse_line(line: str) -> dict[str, Any] | None:
    text = (line or "").strip()
    if not text:
        return None
    try:
        message = json.loads(text)
    except json.JSONDecodeError:
        return None
    return message if isinstance(message, dict) else None


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
