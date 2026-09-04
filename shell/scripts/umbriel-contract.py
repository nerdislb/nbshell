#!/usr/bin/env python3
"""Discover and invoke the narrow nbshell/Umbriel capability contract."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
from typing import Any


CONTRACT_PATH = Path(__file__).resolve().parents[1] / "Catalog/umbriel-capabilities.json"
PROBE_TIMEOUT_SECONDS = 3
COMMAND_PATTERN = re.compile(r"^\s*umbriel\s+([a-z][a-z0-9-]*)", re.MULTILINE)
ACTION_PATTERN = re.compile(r"^\s{2}([a-z][a-z0-9-]*)(?::\S+)?\s{2,}", re.MULTILINE)
VERSION_REVISION_PATTERN = re.compile(r"\(([0-9a-f]{7,40})\)")
WINDOW_ID_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]+$")
FALLBACKS = {"unavailable", "empty"}


class ContractError(Exception):
    """A stable contract or invocation error suitable for CLI reporting."""

    def __init__(self, code: str, message: str, capability: str | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.capability = capability

    def payload(self) -> dict[str, Any]:
        value: dict[str, Any] = {"code": self.code, "message": self.message}
        if self.capability is not None:
            value["capability"] = self.capability
        return value


def load_contract(path: Path = CONTRACT_PATH) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ContractError("contract-unreadable", f"Cannot read Umbriel contract: {error}") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise ContractError("contract-invalid", "Umbriel contract must use schemaVersion 1")
    if value.get("contractVersion") != 1 or value.get("backend") != "umbriel":
        raise ContractError("contract-invalid", "Unsupported Umbriel contract identity")
    revision = value.get("referenceRevision")
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ContractError("contract-invalid", "Umbriel referenceRevision must be a full Git revision")
    capabilities = value.get("capabilities")
    if not isinstance(capabilities, list) or not capabilities:
        raise ContractError("contract-invalid", "Umbriel contract has no capabilities")

    identifiers: set[str] = set()
    for capability in capabilities:
        if not isinstance(capability, dict):
            raise ContractError("contract-invalid", "Umbriel capabilities must be objects")
        identifier = capability.get("id")
        kind = capability.get("kind")
        wire_name = capability.get("wireName")
        fallback = capability.get("fallback")
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z][a-z0-9.-]*", identifier):
            raise ContractError("contract-invalid", "Umbriel capability has an invalid id")
        if identifier in identifiers:
            raise ContractError("contract-invalid", f"Duplicate Umbriel capability: {identifier}")
        identifiers.add(identifier)
        if kind not in {"query", "event", "action"}:
            raise ContractError("contract-invalid", f"Invalid kind for {identifier}", identifier)
        if not isinstance(wire_name, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", wire_name):
            raise ContractError("contract-invalid", f"Invalid wire name for {identifier}", identifier)
        if not isinstance(capability.get("required"), bool):
            raise ContractError("contract-invalid", f"Invalid required flag for {identifier}", identifier)
        if not isinstance(fallback, str):
            raise ContractError("contract-invalid", f"Invalid fallback for {identifier}", identifier)
        if kind == "action":
            argument = capability.get("argument")
            if argument not in {"none", "workspace", "layout", "window-id", "fraction", "quit-mode", "optional-output"}:
                raise ContractError("contract-invalid", f"Invalid argument kind for {identifier}", identifier)
            if wire_name == "spawn":
                raise ContractError("contract-invalid", "The contract must not expose arbitrary process spawning", identifier)
        elif "argument" in capability:
            raise ContractError("contract-invalid", f"Only actions accept arguments: {identifier}", identifier)

    for capability in capabilities:
        fallback = capability["fallback"]
        if fallback not in FALLBACKS and fallback not in identifiers:
            raise ContractError("contract-invalid", f"Unknown fallback for {capability['id']}", capability["id"])
    return value


def resolve_binary(explicit: str | None) -> str | None:
    candidate = explicit or os.environ.get("NBSHELL_UMBRIEL_BINARY")
    if candidate:
        path = Path(candidate).expanduser()
        try:
            resolved = path.resolve(strict=True)
        except OSError:
            return None
        return str(resolved) if resolved.is_file() and os.access(resolved, os.X_OK) else None
    detected = shutil.which("umbriel")
    if detected:
        return detected
    for fallback in (Path("/usr/local/bin/umbriel"), Path.home() / ".local/bin/umbriel"):
        if fallback.is_file() and os.access(fallback, os.X_OK):
            return str(fallback)
    return None


def run_probe(binary: str, arguments: list[str]) -> str:
    try:
        result = subprocess.run(
            [binary, *arguments], text=True, capture_output=True,
            timeout=PROBE_TIMEOUT_SECONDS, check=False, close_fds=True,
        )
    except OSError as error:
        raise ContractError("probe-failed", f"Cannot execute Umbriel: {error}") from error
    except subprocess.TimeoutExpired as error:
        raise ContractError("probe-timeout", "Umbriel capability discovery timed out") from error
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        message = "Umbriel capability discovery failed"
        if detail:
            message += f": {detail[:500]}"
        raise ContractError("probe-failed", message)
    return result.stdout


def parse_events(help_text: str) -> set[str]:
    for line in help_text.splitlines():
        if "events:" not in line:
            continue
        _, names = line.split("events:", 1)
        return {name.strip() for name in names.split(",") if name.strip()}
    return set()


def discover(binary: str, contract: dict[str, Any]) -> dict[str, Any]:
    help_text = run_probe(binary, ["--help"])
    action_text = run_probe(binary, ["msg", "--help"])
    version = run_probe(binary, ["--version"]).strip()
    revision_match = VERSION_REVISION_PATTERN.search(version)
    commands = set(COMMAND_PATTERN.findall(help_text))
    events = parse_events(help_text)
    actions = set(ACTION_PATTERN.findall(action_text))

    rows = []
    for capability in contract["capabilities"]:
        kind = capability["kind"]
        available = capability["wireName"] in {
            "query": commands,
            "event": events,
            "action": actions,
        }[kind]
        rows.append({
            "id": capability["id"],
            "kind": kind,
            "required": capability["required"],
            "available": available,
            "fallback": capability["fallback"],
        })
    return {
        "version": version,
        "revision": revision_match.group(1) if revision_match else None,
        "commands": sorted(commands),
        "events": sorted(events),
        "actions": sorted(actions),
        "capabilities": rows,
    }


def socket_path() -> Path:
    configured = os.environ.get("UMBRIEL_SOCKET")
    if configured:
        return Path(configured)
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    display = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
    return Path(runtime) / f"umbriel-{display}.sock"


def can_connect_socket(path: Path) -> bool:
    try:
        if not path.is_socket():
            return False
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(0.25)
            connection.connect(str(path))
        return True
    except OSError:
        return False


def build_status(contract: dict[str, Any], explicit_binary: str | None) -> dict[str, Any]:
    binary = resolve_binary(explicit_binary)
    path = socket_path()
    errors: list[dict[str, Any]] = []
    discovery: dict[str, Any] | None = None
    if binary is None:
        errors.append({"code": "binary-not-found", "message": "Umbriel executable was not found"})
    else:
        try:
            discovery = discover(binary, contract)
        except ContractError as error:
            errors.append(error.payload())

    if discovery is None:
        capabilities = [{
            "id": item["id"],
            "kind": item["kind"],
            "required": item["required"],
            "available": False,
            "fallback": item["fallback"],
        } for item in contract["capabilities"]]
    else:
        capabilities = discovery["capabilities"]
    missing_required = sorted(
        item["id"] for item in capabilities if item["required"] and not item["available"]
    )
    missing_optional = sorted(
        item["id"] for item in capabilities if not item["required"] and not item["available"]
    )
    revision = discovery["revision"] if discovery else None
    revision_verified = bool(revision and contract["referenceRevision"].startswith(revision))
    compatible = discovery is not None and not missing_required and revision_verified
    socket_available = can_connect_socket(path)

    if discovery is None:
        status = "unavailable"
    elif missing_required or not revision_verified:
        status = "incompatible"
        if missing_required:
            errors.append({
                "code": "missing-required-capability",
                "message": "Umbriel is missing required nbshell capabilities",
                "capabilities": missing_required,
            })
        if not revision_verified:
            errors.append({
                "code": "revision-mismatch",
                "message": "Umbriel revision does not match the tested contract revision",
            })
    elif not socket_available:
        status = "offline"
    elif missing_optional:
        status = "degraded"
    else:
        status = "ready"

    if compatible and not socket_available:
        errors.append({"code": "ipc-unavailable", "message": "Umbriel IPC socket is unavailable"})

    return {
        "schemaVersion": 1,
        "contractVersion": contract["contractVersion"],
        "backend": contract["backend"],
        "referenceRevision": contract["referenceRevision"],
        "status": status,
        "compatible": compatible,
        "runtime": {
            "binary": binary,
            "version": discovery["version"] if discovery else None,
            "revision": revision,
            "revisionMatchesReference": revision_verified,
            "socket": str(path),
            "socketAvailable": socket_available,
        },
        "missingRequired": missing_required,
        "missingOptional": missing_optional,
        "capabilities": capabilities,
        "errors": errors,
    }


def action_map(contract: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {item["id"]: item for item in contract["capabilities"] if item["kind"] == "action"}


def validate_argument(capability: dict[str, Any], value: str | None) -> str | None:
    identifier = capability["id"]
    kind = capability["argument"]
    if kind == "none":
        if value is not None:
            raise ContractError("invalid-argument", f"{identifier} does not accept an argument", identifier)
        return None
    if kind == "optional-output" and value is None:
        return None
    if value is None:
        raise ContractError("invalid-argument", f"{identifier} requires an argument", identifier)
    if kind == "layout":
        if value not in {"scrolling", "dwindle", "master", "toggle"}:
            raise ContractError("invalid-argument", "Layout must be scrolling, dwindle, master, or toggle", identifier)
    elif kind == "workspace":
        if "\0" in value or not value or len(value.encode("utf-8")) > 60_000:
            raise ContractError("invalid-argument", "Workspace selector is empty or too large", identifier)
    elif kind == "window-id":
        if not WINDOW_ID_PATTERN.fullmatch(value):
            raise ContractError("invalid-argument", "Window id has an invalid format", identifier)
    elif kind == "fraction":
        try:
            number = float(value)
        except ValueError as error:
            raise ContractError("invalid-argument", "Window fraction must be a number", identifier) from error
        if not 0.1 <= number <= 1:
            raise ContractError("invalid-argument", "Window fraction must be between 0.1 and 1", identifier)
        value = format(number, "g")
    elif kind == "quit-mode":
        if value != "skip-confirmation":
            raise ContractError("invalid-argument", "Quit mode must be skip-confirmation", identifier)
    elif kind == "optional-output" and ("\0" in value or not value or len(value.encode("utf-8")) > 60_000):
        raise ContractError("invalid-argument", "Output name is empty or too large", identifier)
    return value


def invoke_action(
    contract: dict[str, Any], identifier: str, value: str | None,
    explicit_binary: str | None,
) -> dict[str, Any]:
    capability = action_map(contract).get(identifier)
    if capability is None:
        raise ContractError("unknown-action", f"Unknown nbshell compositor action: {identifier}", identifier)
    argument = validate_argument(capability, value)
    binary = resolve_binary(explicit_binary)
    if binary is None:
        raise ContractError("binary-not-found", "Umbriel executable was not found", identifier)
    effective = capability
    fallback = action_map(contract).get(capability["fallback"])
    available_actions = set(ACTION_PATTERN.findall(run_probe(binary, ["msg", "--help"])))
    if capability["wireName"] not in available_actions:
        if fallback is None or fallback["wireName"] not in available_actions:
            raise ContractError("unsupported-action", f"Umbriel does not support {identifier}", identifier)
        effective = fallback
    wire_action = effective["wireName"]
    if argument is not None:
        wire_action += ":" + argument
    try:
        result = subprocess.run(
            [binary, "msg", wire_action], text=True, capture_output=True,
            timeout=PROBE_TIMEOUT_SECONDS, check=False, close_fds=True,
        )
    except OSError as error:
        raise ContractError("action-failed", f"Cannot execute Umbriel action: {error}", identifier) from error
    except subprocess.TimeoutExpired as error:
        raise ContractError("action-timeout", f"Umbriel action timed out: {identifier}", identifier) from error
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        message = f"Umbriel action failed: {identifier}"
        if detail:
            message += f": {detail[:500]}"
        raise ContractError("action-failed", message, identifier)
    return {
        "ok": True,
        "contractVersion": contract["contractVersion"],
        "capability": identifier,
        "effectiveCapability": effective["id"],
        "fallbackUsed": effective["id"] != identifier,
    }


def emit(value: dict[str, Any], json_output: bool) -> None:
    if json_output:
        print(json.dumps(value, sort_keys=True, separators=(",", ":")))
        return
    if value.get("ok") is False:
        print(value["error"]["message"], file=sys.stderr)
    elif "status" in value:
        runtime = value["runtime"]
        print(f"Umbriel contract: v{value['contractVersion']} ({value['status']})")
        print(f"Binary: {runtime['binary'] or 'not found'}")
        print(f"Version: {runtime['version'] or 'unknown'}")
        print(f"IPC socket: {'available' if runtime['socketAvailable'] else 'unavailable'}")
        print(f"Required capabilities missing: {len(value['missingRequired'])}")
        print(f"Optional capabilities missing: {len(value['missingOptional'])}")
    else:
        print(value["capability"])


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="nbshell Umbriel capability contract")
    commands = root.add_subparsers(dest="command", required=True)
    for name in ("status", "check"):
        command = commands.add_parser(name)
        command.add_argument("--json", action="store_true")
        command.add_argument("--binary")
    action = commands.add_parser("action")
    action.add_argument("name")
    action.add_argument("value", nargs="?")
    action.add_argument("--json", action="store_true")
    action.add_argument("--binary")
    return root


def main(arguments: list[str] | None = None) -> int:
    options = parser().parse_args(arguments)
    json_output = bool(options.json)
    try:
        contract = load_contract()
        if options.command in {"status", "check"}:
            value = build_status(contract, options.binary)
            emit(value, json_output)
            return 0 if options.command == "status" or value["compatible"] else 1
        value = invoke_action(contract, options.name, options.value, options.binary)
        emit(value, json_output)
        return 0
    except ContractError as error:
        emit({
            "ok": False,
            "contractVersion": 1,
            "error": error.payload(),
        }, json_output)
        return 2 if error.code in {"unknown-action", "invalid-argument", "contract-invalid"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
