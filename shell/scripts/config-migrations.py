#!/usr/bin/env python3
"""Migrate nbshell-owned shell configuration without touching plugin or Umbriel state."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import fcntl
import hashlib
import json
import os
import pathlib
import sys
import tempfile
import time
from typing import Any

SCHEMA_VERSION = 1
LEDGER_VERSION = 1
DOMAIN = "nbshell-shell-config"
MIGRATION_ID = "0001-config-schema-v1"
MIGRATION_CHECKSUM = hashlib.sha256(
    b"0001-config-schema-v1:add-top-level-schemaVersion=1"
).hexdigest()
VALID_STATUSES = {"pending", "applied", "failed"}


class StateError(RuntimeError):
    """Persistent state is invalid or cannot be migrated safely."""


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def fsync_directory(path: pathlib.Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def ensure_directory(path: pathlib.Path) -> None:
    """Create a private directory tree and durably link each new component."""
    missing: list[pathlib.Path] = []
    cursor = path
    while not cursor.exists():
        missing.append(cursor)
        cursor = cursor.parent
    if not cursor.is_dir():
        raise StateError(f"directory parent is not a directory: {cursor}")
    for directory in reversed(missing):
        try:
            directory.mkdir(mode=0o700)
        except FileExistsError:
            if not directory.is_dir():
                raise
        fsync_directory(directory.parent)


def atomic_write(path: pathlib.Path, payload: bytes) -> None:
    ensure_directory(path.parent)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = pathlib.Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def read_json_object(path: pathlib.Path, label: str) -> tuple[dict[str, Any], bytes]:
    try:
        raw = path.read_bytes()
    except FileNotFoundError as error:
        raise StateError(f"{label} is missing: {path}") from error
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise StateError(f"{label} is not valid UTF-8 JSON: {path}: {error}") from error
    if not isinstance(value, dict):
        raise StateError(f"{label} must contain a JSON object: {path}")
    return value, raw


def config_schema(config: dict[str, Any]) -> int | None:
    if "schemaVersion" not in config:
        return None
    value = config["schemaVersion"]
    if isinstance(value, bool) or not isinstance(value, int):
        raise StateError("config.json field 'schemaVersion' must be an integer")
    if value < 1:
        raise StateError("config.json field 'schemaVersion' must be at least 1")
    if value > SCHEMA_VERSION:
        raise StateError(
            f"config.json schema {value} is newer than this nbshell supports ({SCHEMA_VERSION}); "
            "downgrade is not supported"
        )
    return value


def empty_ledger() -> dict[str, Any]:
    return {"ledgerVersion": LEDGER_VERSION, "domain": DOMAIN, "migrations": {}}


def read_ledger(path: pathlib.Path) -> tuple[dict[str, Any], bool]:
    if not path.exists():
        return empty_ledger(), False
    ledger, _ = read_json_object(path, "migration ledger")
    if ledger.get("ledgerVersion") != LEDGER_VERSION:
        raise StateError(
            f"migration ledger has unsupported ledgerVersion: {ledger.get('ledgerVersion')!r}"
        )
    if ledger.get("domain") != DOMAIN:
        raise StateError(f"migration ledger has unexpected domain: {ledger.get('domain')!r}")
    entries = ledger.get("migrations")
    if not isinstance(entries, dict):
        raise StateError("migration ledger field 'migrations' must be an object")
    unknown = sorted(set(entries) - {MIGRATION_ID})
    if unknown:
        raise StateError(
            "migration ledger contains migrations unknown to this nbshell release: "
            + ", ".join(unknown)
        )
    for migration_id, entry in entries.items():
        if not isinstance(entry, dict):
            raise StateError(f"migration ledger entry {migration_id!r} must be an object")
        if entry.get("status") not in VALID_STATUSES:
            raise StateError(f"migration ledger entry {migration_id!r} has an invalid status")
        if entry.get("checksum") != MIGRATION_CHECKSUM:
            raise StateError(f"migration ledger entry {migration_id!r} has an unexpected checksum")
    return ledger, True


def paths_from_environment() -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    home = pathlib.Path.home()
    config_home = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    state_home = pathlib.Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    config_path = config_home / "nbshell/config.json"
    state_dir = state_home / "nbshell"
    return config_path, state_dir / "config-migrations.json", state_dir


def migration_lock(state_dir: pathlib.Path):
    ensure_directory(state_dir)
    lock_path = state_dir / "config-migration.lock"
    handle = lock_path.open("a+b")
    os.chmod(lock_path, 0o600)
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    return handle


def backup_config(state_dir: pathlib.Path, source: bytes) -> pathlib.Path:
    digest = hashlib.sha256(source).hexdigest()
    backup = state_dir / "migration-backups" / f"{MIGRATION_ID}-{digest[:16]}.json"
    if backup.exists():
        if backup.read_bytes() != source:
            raise StateError(f"existing migration backup does not match its source: {backup}")
        return backup
    atomic_write(backup, source)
    return backup


def effective_status(
    config: dict[str, Any], ledger: dict[str, Any], ledger_exists: bool
) -> dict[str, Any]:
    schema = config_schema(config)
    entry = ledger["migrations"].get(MIGRATION_ID)
    if entry:
        migration = {"id": MIGRATION_ID, **entry, "recorded": True}
    elif schema == SCHEMA_VERSION:
        migration = {
            "id": MIGRATION_ID,
            "status": "applied",
            "checksum": MIGRATION_CHECKSUM,
            "recorded": False,
            "baseline": True,
        }
    else:
        migration = {
            "id": MIGRATION_ID,
            "status": "pending",
            "checksum": MIGRATION_CHECKSUM,
            "recorded": False,
        }
    return {
        "ok": migration["status"] == "applied" and schema == SCHEMA_VERSION,
        "domain": DOMAIN,
        "schemaVersion": schema,
        "targetSchemaVersion": SCHEMA_VERSION,
        "ledgerVersion": LEDGER_VERSION,
        "ledgerExists": ledger_exists,
        "migrations": [migration],
    }


def write_ledger(path: pathlib.Path, ledger: dict[str, Any]) -> None:
    atomic_write(path, json_bytes(ledger))


def apply_migrations(
    config_path: pathlib.Path, ledger_path: pathlib.Path, state_dir: pathlib.Path, dry_run: bool
) -> dict[str, Any]:
    if dry_run:
        if not config_path.exists():
            ledger, ledger_exists = read_ledger(ledger_path)
            if ledger["migrations"]:
                raise StateError("shell configuration is missing but migration ledger is not empty")
            return {
                "ok": True,
                "domain": DOMAIN,
                "schemaVersion": None,
                "targetSchemaVersion": SCHEMA_VERSION,
                "ledgerVersion": LEDGER_VERSION,
                "ledgerExists": ledger_exists,
                "migrations": [{"id": MIGRATION_ID, "status": "pending", "baseline": True}],
                "dryRun": True,
                "wouldCreateConfig": True,
                "wouldMutateConfig": False,
                "wouldWriteLedger": True,
            }
        config, _ = read_json_object(config_path, "shell configuration")
        ledger, ledger_exists = read_ledger(ledger_path)
        status = effective_status(config, ledger, ledger_exists)
        status["dryRun"] = True
        status["wouldMutateConfig"] = config_schema(config) is None
        status["wouldWriteLedger"] = ledger["migrations"].get(MIGRATION_ID) is None
        return status

    with migration_lock(state_dir):
        testing = os.environ.get("NBSHELL_MIGRATION_TESTING") == "1"
        ready_file = os.environ.get("NBSHELL_MIGRATION_TEST_READY_FILE") if testing else None
        if ready_file:
            pathlib.Path(ready_file).write_text("locked\n", encoding="utf-8")
        hold = os.environ.get("NBSHELL_MIGRATION_TEST_HOLD_LOCK") if testing else None
        if hold:
            time.sleep(float(hold))

        ledger, ledger_exists = read_ledger(ledger_path)
        if not config_path.exists():
            if ledger["migrations"]:
                raise StateError("shell configuration is missing but migration ledger is not empty")
            config = {"schemaVersion": SCHEMA_VERSION}
            atomic_write(config_path, json_bytes(config))
            ledger["migrations"][MIGRATION_ID] = {
                "status": "applied",
                "checksum": MIGRATION_CHECKSUM,
                "completedAt": utc_now(),
                "baseline": True,
                "fresh": True,
            }
            write_ledger(ledger_path, ledger)
            return effective_status(config, ledger, True)

        config, source = read_json_object(config_path, "shell configuration")
        schema = config_schema(config)
        entry = ledger["migrations"].get(MIGRATION_ID)

        if entry and entry["status"] == "failed":
            raise StateError(
                f"migration {MIGRATION_ID} previously failed: {entry.get('error', 'unknown error')}; "
                "inspect the backup and ledger before retrying"
            )
        if entry and entry["status"] == "applied":
            if schema != SCHEMA_VERSION:
                raise StateError(
                    f"migration {MIGRATION_ID} is recorded as applied but config.json is not schema {SCHEMA_VERSION}"
                )
            return effective_status(config, ledger, ledger_exists)

        pending_backup: bytes | None = None
        if entry and entry["status"] == "pending":
            backup_value = entry.get("backup")
            if not isinstance(backup_value, str):
                raise StateError(f"pending migration {MIGRATION_ID} has no usable backup path")
            backup = pathlib.Path(backup_value)
            if not backup.is_file():
                raise StateError(f"pending migration {MIGRATION_ID} cannot resume because its backup is missing")
            pending_backup = backup.read_bytes()
            source_checksum = entry.get("sourceChecksum")
            if source_checksum is not None and (
                not isinstance(source_checksum, str)
                or hashlib.sha256(pending_backup).hexdigest() != source_checksum
            ):
                raise StateError(f"pending migration {MIGRATION_ID} cannot resume because its backup is damaged")

        if schema == SCHEMA_VERSION:
            if entry and entry["status"] == "pending":
                entry["status"] = "applied"
                entry["completedAt"] = utc_now()
                entry["recoveredAfterInterruption"] = True
            else:
                ledger["migrations"][MIGRATION_ID] = {
                    "status": "applied",
                    "checksum": MIGRATION_CHECKSUM,
                    "completedAt": utc_now(),
                    "baseline": True,
                }
            write_ledger(ledger_path, ledger)
            return effective_status(config, ledger, True)

        if schema is not None:
            raise StateError(f"no supported migration path from config schema {schema}")

        if entry and entry["status"] == "pending":
            if pending_backup != source:
                raise StateError(
                    f"pending migration {MIGRATION_ID} cannot resume because config.json changed after backup"
                )
        else:
            backup = backup_config(state_dir, source)
            ledger["migrations"][MIGRATION_ID] = {
                "status": "pending",
                "checksum": MIGRATION_CHECKSUM,
                "sourceChecksum": hashlib.sha256(source).hexdigest(),
                "startedAt": utc_now(),
                "backup": str(backup),
            }
            write_ledger(ledger_path, ledger)

        if testing and os.environ.get("NBSHELL_MIGRATION_TEST_INTERRUPT") == "after-backup":
            os._exit(97)

        try:
            if testing and os.environ.get("NBSHELL_MIGRATION_TEST_FAIL") == MIGRATION_ID:
                raise StateError("injected migration failure")
            migrated = copy.deepcopy(config)
            migrated["schemaVersion"] = SCHEMA_VERSION
            config_schema(migrated)
        except Exception as error:
            failed = ledger["migrations"][MIGRATION_ID]
            failed["status"] = "failed"
            failed["failedAt"] = utc_now()
            failed["error"] = str(error)
            write_ledger(ledger_path, ledger)
            raise StateError(f"migration {MIGRATION_ID} failed: {error}") from error

        # I/O failures from this point leave the durable pending entry intact.
        # That state is resumable even if replacement succeeded but the applied
        # ledger update did not.
        atomic_write(config_path, json_bytes(migrated))
        if testing and os.environ.get("NBSHELL_MIGRATION_TEST_INTERRUPT") == "after-replace":
            os._exit(98)

        applied = ledger["migrations"][MIGRATION_ID]
        applied["status"] = "applied"
        applied["completedAt"] = utc_now()
        applied.pop("failedAt", None)
        applied.pop("error", None)
        write_ledger(ledger_path, ledger)
        return effective_status(migrated, ledger, True)


def read_status(config_path: pathlib.Path, ledger_path: pathlib.Path) -> dict[str, Any]:
    if not config_path.exists():
        ledger, ledger_exists = read_ledger(ledger_path)
        if ledger["migrations"]:
            raise StateError("shell configuration is missing but migration ledger is not empty")
        return {
            "ok": False,
            "domain": DOMAIN,
            "schemaVersion": None,
            "targetSchemaVersion": SCHEMA_VERSION,
            "ledgerVersion": LEDGER_VERSION,
            "ledgerExists": ledger_exists,
            "migrations": [
                {
                    "id": MIGRATION_ID,
                    "status": "pending",
                    "checksum": MIGRATION_CHECKSUM,
                    "recorded": False,
                    "baseline": True,
                }
            ],
        }
    config, _ = read_json_object(config_path, "shell configuration")
    ledger, ledger_exists = read_ledger(ledger_path)
    return effective_status(config, ledger, ledger_exists)


def print_result(result: dict[str, Any], as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return
    migration = result["migrations"][0]
    schema = result["schemaVersion"]
    print(f"Shell config schema: {schema if schema is not None else 'legacy'} -> {result['targetSchemaVersion']}")
    print(f"{migration['id']}: {migration['status']}")
    if migration.get("backup"):
        print(f"Backup: {migration['backup']}")
    if migration.get("error"):
        print(f"Error: {migration['error']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Inspect or migrate nbshell shell configuration.")
    parser.add_argument("action", choices=("status", "apply"), nargs="?", default="status")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--dry-run", action="store_true", help="report changes without writing them")
    args = parser.parse_args(argv)
    if args.action == "status" and args.dry_run:
        parser.error("--dry-run is only valid with apply")

    config_path, ledger_path, state_dir = paths_from_environment()
    try:
        if args.action == "apply":
            result = apply_migrations(config_path, ledger_path, state_dir, args.dry_run)
        else:
            result = read_status(config_path, ledger_path)
    except (OSError, StateError) as error:
        if args.json:
            print(json.dumps({"ok": False, "error": str(error)}, sort_keys=True))
        else:
            print(f"nbshell config migration error: {error}", file=sys.stderr)
        return 1
    print_result(result, args.json)
    return 0 if result["ok"] or args.dry_run else 1


if __name__ == "__main__":
    raise SystemExit(main())
