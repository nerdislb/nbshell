#!/usr/bin/env python3
"""Exercise the release test gate with actual, tiny Meson projects."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('update', ROOT / 'shell/scripts/umbriel-update.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    empty = root / 'empty'; empty.mkdir()
    (empty / 'meson.build').write_text("project('renamed-upstream')\n")
    try:
        update.build_project(empty, "umbriel")
        raise AssertionError('Zero compositor tests were accepted')
    except RuntimeError as exc:
        assert 'defines no tests' in str(exc)
    feature = root / 'feature'; feature.mkdir()
    (feature / 'meson.options').write_text("option('tests', type: 'feature', value: 'auto')\n")
    (feature / 'meson.build').write_text("project('umbriel')\nif get_option('tests').enabled()\n test('release gate', find_program('true'))\nendif\n")
    try:
        update.build_project(feature, "umbriel")
        raise AssertionError('Missing compositor binary was accepted')
    except RuntimeError as exc:
        assert "Cannot execute Umbriel" in str(exc), str(exc)
    tests = json.loads(subprocess.check_output(['meson', 'introspect', str(feature / 'build-nbshell'), '--tests']))
    assert len(tests) == 1
print('Actual Meson zero-test rejection and release feature enablement: OK')
