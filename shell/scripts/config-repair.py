#!/usr/bin/env python3
"""Explicit, previewed config restoration with retained originals and crash recovery."""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import pathlib
import re
import runpy
import sys

M = runpy.run_path(str(pathlib.Path(__file__).with_name("config-migrations.py")))


def read_optional(path):
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def encode(value):
    return None if value is None else base64.b64encode(value).decode("ascii")


def decode(value):
    return None if value is None else base64.b64decode(value, validate=True)


def inspect():
    config, ledger, state = M["paths_from_environment"]()
    try:
        status = M["read_status"](config, ledger)
        error = "" if status["ok"] else "Configuration migration requires attention."
    except (OSError, RuntimeError, ValueError) as exc:
        status, error = {"ok": False}, str(exc)
    pending = read_optional(state / "repair-pending.json")
    return {"ok": status["ok"] and pending is None, "error": error,
            "configPath": str(config), "pendingRepair": json.loads(pending) if pending else None,
            "backups": [str(p) for p in sorted((state / "migration-backups").glob("*.json"))]}


def preview(candidate):
    config, ledger, state = M["paths_from_environment"]()
    value, _ = M["read_json_object"](candidate, "repair candidate")
    schema = M["config_schema"](value)
    for step in M["registry"]():
        if (schema or 0) < step["target"]:
            if schema != step["source"]:
                raise RuntimeError("No migration path for repair candidate")
            value = step["transform"](copy.deepcopy(value))
            schema = M["config_schema"](value)
            if schema != step["target"]:
                raise RuntimeError("Repair migration produced an unexpected schema")
    payload = M["json_bytes"](value)
    with M["migration_lock"](state, timeout=5):
        if (state / "repair-pending.json").exists():
            raise RuntimeError("An interrupted repair must be resumed before previewing another candidate")
        old_config, old_ledger = read_optional(config), read_optional(ledger)
        # Keep even corrupt originals verbatim in the private, immutable plan.
        new_ledger = M["empty_ledger"]()
        for step in M["registry"]():
            new_ledger["migrations"][step["id"]] = {
                "status": "applied", "checksum": step["checksum"],
                "baseline": True, "repair": True}
        plan = {"version": 1, "configPath": str(config), "ledgerPath": str(ledger),
                "candidate": str(candidate.resolve()), "beforeConfig": encode(old_config),
                "beforeLedger": encode(old_ledger), "afterConfig": encode(payload),
                "afterLedger": encode(M["json_bytes"](new_ledger))}
        raw = M["json_bytes"](plan)
        token = hashlib.sha256(raw).hexdigest()
        destination = state / "config-repairs" / (token + ".json")
        if destination.exists() and destination.read_bytes() != raw:
            raise RuntimeError("Repair preview changed unexpectedly")
        M["atomic_write"](destination, raw)
    return {"ok": True, "token": token, "candidate": plan["candidate"],
            "backup": str(destination), "settingCount": len(value) - 1,
            "message": "Restore this candidate and rebuild migration history. Current file bytes and history are retained in the private repair record. Settings absent from the candidate will not be retained."}


def apply(token):
    if not re.fullmatch(r"[0-9a-f]{64}", token):
        raise RuntimeError("Invalid repair token; preview a candidate first")
    config, ledger, state = M["paths_from_environment"]()
    with M["migration_lock"](state, timeout=5):
        path = state / "config-repairs" / (token + ".json")
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != token:
            raise RuntimeError("Repair record is damaged")
        plan = json.loads(raw)
        if plan["version"] != 1 or plan["configPath"] != str(config) or plan["ledgerPath"] != str(ledger):
            raise RuntimeError("Repair record belongs to a different configuration")
        journal = state / "repair-pending.json"
        pending = read_optional(journal)
        if pending is not None and json.loads(pending) != {"token": token}:
            raise RuntimeError("A different repair is pending; resume it first")
        pairs = [(config, decode(plan["beforeConfig"]), decode(plan["afterConfig"])),
                 (ledger, decode(plan["beforeLedger"]), decode(plan["afterLedger"]))]
        if pending is None and all(read_optional(target) == after for target, before, after in pairs):
            return {"ok": True, "backup": str(path), "message": "This repair is already applied. Retry startup."}
        # Before the first commit both files must still match the reviewed state.
        # During replay each file may be either before or after its replacement.
        for target, before, after in pairs:
            current = read_optional(target)
            if current != before and (pending is None or current != after):
                raise RuntimeError("Configuration or history changed after preview; preview again. Originals were not replaced.")
        M["atomic_write"](journal, M["json_bytes"]({"token": token}))
        for target, before, after in pairs:
            if read_optional(target) not in (before, after):
                raise RuntimeError("Configuration changed during repair; inspect the pending repair")
            M["atomic_write"](target, after)
        journal.unlink()
        M["fsync_directory"](state)
    return {"ok": True, "backup": str(path), "message": "Configuration restored. Retry startup to load it."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    commands.add_parser("inspect")
    commands.add_parser("preview").add_argument("candidate", type=pathlib.Path)
    commands.add_parser("apply").add_argument("token")
    args = parser.parse_args()
    try:
        result = inspect() if args.action == "inspect" else preview(args.candidate) if args.action == "preview" else apply(args.token)
    except (OSError, RuntimeError, ValueError, KeyError) as exc:
        result = {"ok": False, "error": str(exc)}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
