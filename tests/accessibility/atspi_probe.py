#!/usr/bin/env python3
"""Capture a bounded native AT-SPI snapshot of the running nbshell process."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import threading
from typing import Any, Iterable

from gi.repository import GLib

try:
    import pyatspi
except ImportError as error:  # pragma: no cover - exercised on systems without AT-SPI
    raise SystemExit(
        "python-atspi is required; install it explicitly before running this probe"
    ) from error

DEFAULT_APP_PATTERN = r"(?:nbshell|quickshell)"
DEFAULT_MAX_DEPTH = 8
DEFAULT_MAX_NODES = 500


def application_pid(application: Any) -> int | None:
    try:
        pid = int(application.get_process_id())
    except (AttributeError, TypeError, ValueError, RuntimeError, GLib.Error):
        return None
    return pid if pid > 0 else None


def find_application(
    applications: Iterable[Any], pattern: str, pid: int | None = None
) -> Any | None:
    matcher = re.compile(pattern, re.IGNORECASE)
    candidates = list(applications)
    if pid is not None:
        for application in candidates:
            if application_pid(application) == pid:
                return application
        return None
    for application in candidates:
        name = safe_text(application, "name")
        if matcher.search(name):
            return application
    return None


def safe_text(node: Any, attribute: str) -> str:
    try:
        value = getattr(node, attribute)
    except (AttributeError, RuntimeError, GLib.Error):
        return ""
    return str(value or "")


def normalize_attributes(raw_attributes: Iterable[Any]) -> list[str]:
    return [str(attribute) for attribute in raw_attributes]


def node_attributes(node: Any) -> list[str]:
    try:
        return normalize_attributes(node.getAttributes())
    except (AttributeError, RuntimeError, GLib.Error):
        return []


def node_states(node: Any) -> list[str]:
    try:
        states = node.getState().getStates()
    except (AttributeError, RuntimeError, GLib.Error):
        return []
    names: list[str] = []
    for state in states:
        try:
            names.append(str(pyatspi.stateToString(state)))
        except (TypeError, ValueError, RuntimeError, GLib.Error):
            names.append(str(state))
    return sorted(set(names))


def node_actions(node: Any) -> list[str]:
    try:
        interface = node.queryAction()
    except (AttributeError, NotImplementedError, RuntimeError, GLib.Error):
        return []
    actions: list[str] = []
    try:
        count = int(interface.nActions)
    except (AttributeError, TypeError, ValueError, RuntimeError, GLib.Error):
        return []
    for index in range(count):
        try:
            name = str(interface.getName(index) or "")
        except (RuntimeError, GLib.Error):
            continue
        if name:
            actions.append(name)
    return actions


def stable_id(attributes: Iterable[str]) -> str:
    for key in ("id", "accessible-id", "accessibleId", "automation-id"):
        prefix = f"{key}:"
        for attribute in attributes:
            if attribute.startswith(prefix):
                return attribute[len(prefix):]
    return ""


def iter_children(node: Any) -> Iterable[Any]:
    try:
        count = int(node.childCount)
    except (AttributeError, TypeError, ValueError, RuntimeError, GLib.Error):
        return
    for index in range(max(0, count)):
        try:
            child = node.getChildAtIndex(index)
        except (AttributeError, RuntimeError, GLib.Error):
            continue
        if child is not None:
            yield child


def serialize_tree(
    root: Any, max_depth: int = DEFAULT_MAX_DEPTH, max_nodes: int = DEFAULT_MAX_NODES
) -> tuple[dict[str, Any], int, bool]:
    count = 0
    truncated = False

    def visit(node: Any, depth: int) -> dict[str, Any]:
        nonlocal count, truncated
        count += 1
        attributes = node_attributes(node)
        record: dict[str, Any] = {
            "role": role_name(node),
            "name": safe_text(node, "name"),
            "description": safe_text(node, "description"),
            "states": node_states(node),
            "actions": node_actions(node),
            "id": stable_id(attributes),
            "attributes": attributes,
            "children": [],
        }
        if depth >= max_depth:
            if any(True for _ in iter_children(node)):
                record["children_truncated"] = True
                truncated = True
            return record
        for child in iter_children(node):
            if count >= max_nodes:
                record["children_truncated"] = True
                truncated = True
                break
            record["children"].append(visit(child, depth + 1))
        return record

    return visit(root, 0), count, truncated


def tree_is_empty(tree: dict[str, Any], node_count: int) -> bool:
    return node_count == 1 and not tree.get("children")


def role_name(node: Any) -> str:
    try:
        return str(node.getRoleName() or "")
    except (AttributeError, RuntimeError, GLib.Error):
        return ""


def desktop_applications() -> list[Any]:
    desktop = pyatspi.Registry.getDesktop(0)
    return list(iter_children(desktop))


def event_record(event: Any) -> dict[str, Any]:
    source = getattr(event, "source", None)
    return {
        "type": str(getattr(event, "type", "")),
        "role": role_name(source) if source is not None else "",
        "name": safe_text(source, "name") if source is not None else "",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def collect_focus_events(seconds: float) -> list[dict[str, Any]]:
    if seconds <= 0:
        return []
    events: list[dict[str, Any]] = []

    def on_event(event: Any) -> None:
        events.append(event_record(event))

    def stop_registry() -> None:
        try:
            pyatspi.Registry.stop()
        except (RuntimeError, GLib.Error):
            pass

    timer = threading.Timer(seconds, stop_registry)
    pyatspi.Registry.registerEventListener(
        on_event, "object:state-changed:focused"
    )
    timer.start()
    try:
        pyatspi.Registry.start()
    finally:
        timer.cancel()
        try:
            pyatspi.Registry.deregisterEventListener(
                on_event, "object:state-changed:focused"
            )
        except (RuntimeError, GLib.Error):
            pass
    return events


def default_output_path() -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return Path("/tmp") / f"nbshell-atspi-{stamp}.json"


def write_private_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            descriptor = -1
            json.dump(payload, output, indent=2, ensure_ascii=False)
            output.write("\n")
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture a bounded JSON snapshot from nbshell's native AT-SPI tree."
    )
    parser.add_argument("--app", default=DEFAULT_APP_PATTERN, help="application-name regex")
    parser.add_argument("--pid", type=int, help="match the exported application by process ID")
    parser.add_argument("--max-depth", type=int, default=DEFAULT_MAX_DEPTH)
    parser.add_argument("--max-nodes", type=int, default=DEFAULT_MAX_NODES)
    parser.add_argument(
        "--events-seconds",
        type=float,
        default=0,
        help="also collect focused-state events for this many seconds",
    )
    parser.add_argument("--output", type=Path, default=default_output_path())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.max_depth < 0 or args.max_nodes < 1 or args.events_seconds < 0:
        raise SystemExit("max-depth and events-seconds must be non-negative; max-nodes must be positive")

    applications = desktop_applications()
    application = find_application(applications, args.app, args.pid)
    if application is None:
        visible = [
            {"name": safe_text(app, "name"), "pid": application_pid(app)}
            for app in applications
        ]
        print(
            "nbshell/quickshell is not exported through AT-SPI. "
            "Check org.a11y.Status IsEnabled/ScreenReaderEnabled or run an "
            "isolated process with QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1.",
            file=sys.stderr,
        )
        print(json.dumps({"exported_applications": visible}, ensure_ascii=False), file=sys.stderr)
        return 2

    tree, node_count, truncated = serialize_tree(
        application, max_depth=args.max_depth, max_nodes=args.max_nodes
    )
    payload = {
        "schema_version": 1,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "application": {
            "name": safe_text(application, "name"),
            "pid": application_pid(application),
        },
        "node_count": node_count,
        "truncated": truncated,
        "tree": tree,
        "focus_events": collect_focus_events(args.events_seconds),
    }
    write_private_json(args.output, payload)
    print(args.output)
    if tree_is_empty(tree, node_count):
        print(
            "The application is registered, but its AT-SPI tree is empty. "
            "Check the Qt bridge status and the window toolkit's accessibility integration.",
            file=sys.stderr,
        )
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
