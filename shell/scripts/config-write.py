#!/usr/bin/env python3
"""Apply shell settings under the migration lock, preserving unrelated changes."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import runpy
import sys

M = runpy.run_path(str(Path(__file__).with_name('config-migrations.py')))
MAX_REQUEST = 1024 * 1024


class ConflictError(RuntimeError):
    pass


def update_config(transform, *, create=False):
    path, ledger, state = M['paths_from_environment']()
    if create and not path.exists():
        M['apply_migrations'](path, ledger, state, False, lock_timeout=5.0)
    with M['migration_lock'](state, timeout=5.0):
        current, source = M['read_json_object'](path, 'shell configuration')
        if M['config_schema'](current) != M['SCHEMA_VERSION']:
            raise ValueError("Run 'nbshell migrate apply' before changing settings")
        json.dumps(current, allow_nan=False)
        updated = transform(copy.deepcopy(current))
        if not isinstance(updated, dict) or M['config_schema'](updated) != current['schemaVersion']:
            raise ValueError('Settings writers cannot change schemaVersion')
        json.dumps(updated, allow_nan=False)
        payload = M['json_bytes'](updated)
        # Detect non-cooperating editors seen during the transaction. Editors
        # must use our lock to eliminate the final check/replace race as well.
        observed = path.read_bytes() if path.exists() else None
        if observed != source:
            raise ConflictError('Configuration changed during the write; review and retry')
        if not equal(updated, current):
            M['atomic_write'](path, payload)
        else:
            # A replay can follow replacement whose acknowledgement/fsync failed.
            with path.open('rb') as handle:
                import os
                os.fsync(handle.fileno())
            M['fsync_directory'](path.parent)
        return updated


def equal(left, right):
    # JSON has one numeric type, but booleans are not numbers.
    if type(left) in (int, float) and type(right) in (int, float):
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(equal(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(equal(a, b) for a, b in zip(left, right))
    return left == right


def apply_patch(patch):
    if not isinstance(patch, dict) or not patch or len(patch) > 1024:
        raise ValueError('Expected a non-empty settings patch')
    for key, change in patch.items():
        if key == 'schemaVersion' or not isinstance(change, dict):
            raise ValueError('Invalid settings patch or reserved schemaVersion')
        if not isinstance(change.get('present'), bool) or 'value' not in change:
            raise ValueError('Each change needs its previous presence and new value')
        if change['present'] and 'before' not in change:
            raise ValueError('Each existing setting needs its previous value')
    def transform(current):
        for key, change in patch.items():
            present = key in current
            matches = present == change['present'] and (not present or equal(current[key], change['before']))
            already_applied = present and equal(current[key], change['value'])
            if not matches and not already_applied:
                raise ConflictError('An edited setting changed elsewhere; review and retry')
        for key, change in patch.items():
            current[key] = change['value']
        return current
    return update_config(transform)


def main():
    try:
        request = sys.stdin.buffer.read(MAX_REQUEST + 1)
        if len(request) > MAX_REQUEST:
            raise ValueError('Settings patch is too large')
        patch = json.loads(request, parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Non-finite JSON value')))
        apply_patch(patch)
        print(json.dumps({'ok': True}))
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(json.dumps({'ok': False, 'error': str(error), 'conflict': isinstance(error, ConflictError), 'uncertain': isinstance(error, OSError)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
