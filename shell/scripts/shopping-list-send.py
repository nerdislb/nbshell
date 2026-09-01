#!/usr/bin/env python3
"""Resolve one exact WhatsApp group and send a prepared shopping-list message."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections.abc import Callable, Sequence
from typing import Any

Runner = Callable[..., subprocess.CompletedProcess[str]]


def result(success: bool, message: str, *, code: str = "") -> dict[str, Any]:
    return {"success": success, "message": message, "code": code}


def exact_groups(payload: Any, target: str) -> list[dict[str, Any]]:
    if not isinstance(payload, dict) or payload.get("success") is not True:
        return []
    rows = payload.get("data")
    if not isinstance(rows, list):
        return []
    folded = target.casefold()
    return [
        row for row in rows
        if isinstance(row, dict)
        and row.get("kind") == "group"
        and str(row.get("name", "")).casefold() == folded
        and str(row.get("jid", "")).endswith("@g.us")
    ]


def delivery_accepted(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    if payload.get("sent") is True:
        return True
    data = payload.get("data")
    return isinstance(data, dict) and data.get("sent") is True


def run_command(args: Sequence[str], runner: Runner) -> subprocess.CompletedProcess[str]:
    return runner(
        list(args),
        check=False,
        capture_output=True,
        text=True,
        timeout=45,
    )


def send(target: str, message: str, runner: Runner = subprocess.run) -> tuple[int, dict[str, Any]]:
    if not message.strip():
        return 2, result(False, "The shopping list is empty.", code="empty")

    try:
        lookup = run_command([
            "wacli", "--read-only", "--json", "chats", "list",
            "--query", target, "--limit", "50",
        ], runner)
    except FileNotFoundError:
        return 4, result(False, "WhatsApp command line support is not installed.", code="missing-wacli")
    except subprocess.TimeoutExpired:
        return 5, result(False, "WhatsApp did not answer in time. Try again.", code="timeout")

    if lookup.returncode != 0:
        detail = lookup.stderr.strip() or "Could not read WhatsApp chats."
        return 3, result(False, detail, code="lookup-failed")

    try:
        groups = exact_groups(json.loads(lookup.stdout or "{}"), target)
    except json.JSONDecodeError:
        return 3, result(False, "WhatsApp returned an unreadable chat list.", code="lookup-invalid")

    if not groups:
        return 3, result(
            False,
            f'Group "{target}" is not synced yet. Send one message in the group, then try again.',
            code="group-not-found",
        )
    if len(groups) > 1:
        return 3, result(
            False,
            f'More than one exact group is named "{target}". Rename one before sending.',
            code="group-ambiguous",
        )

    try:
        delivery = run_command([
            "wacli", "--lock-wait", "30s", "--json", "send", "text",
            "--to", str(groups[0]["jid"]), "--message", message,
        ], runner)
    except FileNotFoundError:
        return 4, result(False, "WhatsApp command line support is not installed.", code="missing-wacli")
    except subprocess.TimeoutExpired:
        return 5, result(False, "Sending took too long. Check WhatsApp before retrying.", code="timeout")

    if delivery.returncode != 0:
        detail = delivery.stderr.strip()
        try:
            payload = json.loads(delivery.stdout or "{}")
            detail = str(payload.get("error") or payload.get("message") or detail)
        except json.JSONDecodeError:
            pass
        return delivery.returncode, result(False, detail or "WhatsApp could not send the list.", code="send-failed")

    try:
        accepted = delivery_accepted(json.loads(delivery.stdout or "{}"))
    except json.JSONDecodeError:
        accepted = False
    if not accepted:
        return 6, result(
            False,
            "WhatsApp did not return a send confirmation. Check the group before retrying.",
            code="send-unconfirmed",
        )

    return 0, result(True, f'Sent to "{target}".', code="sent")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--to", required=True)
    parser.add_argument("--message", required=True)
    args = parser.parse_args()
    exit_code, payload = send(args.to, args.message)
    print(json.dumps(payload, ensure_ascii=False))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
