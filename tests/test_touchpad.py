"""Real isolated config/curve tests: no live compositor writes."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('touchpad', ROOT / 'shell/scripts/touchpad.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class TouchpadTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for key, value in {'MAIN': self.root/'umbriel/config.toml', 'OWNED': self.root/'umbriel/nbshell-touchpad.toml', 'STORE': self.root/'state', 'JOURNAL': self.root/'state/pending.json'}.items():
            p = patch.object(m, key, value); p.start(); self.addCleanup(p.stop)
        m.MAIN.parent.mkdir()
        m.MAIN.write_text('# preserve me\n[include]\nfiles = ["base.toml"]\n\n[general]\nshow_cheatsheet = false\n')
        (m.MAIN.parent/'base.toml').write_text('[input.touchpad]\ntap = true\nsensitivity = 0.2\n')
        p=patch.object(m,'devices',return_value=[{'name':'Test Touchpad'}]);p.start();self.addCleanup(p.stop)
        self.reload=patch.object(m,'reload').start();self.addCleanup(patch.stopall)

    def payload(self, **changes):
        state=m.status(); settings=copy.deepcopy(state['settings']);settings.update(changes)
        return {'revision':state['revision'],'settings':settings}

    def test_curve_matches_upstream_js_and_real_libinput(self):
        curves=[m.DEFAULT_CURVE,dict(precision=.01,start=0,end=4,fast=.35),dict(precision=.5,start=3.8,end=4,fast=10)]
        js=ROOT/'shell/Touchpad/Curve.js'
        for curve in curves:
            points=m.curve_points(curve)
            expected=json.loads(subprocess.check_output(['node','-e',f'console.log(JSON.stringify(require({json.dumps(str(js))}).points({json.dumps(curve)})))'],text=True))
            self.assertEqual(points,expected)
            m.native_validate(points)
        with self.assertRaises(ValueError):m.native_validate([0]*81)

    def test_apply_restore_and_roundtrip_keep_unrelated_config(self):
        original=m.MAIN.read_text()
        m.apply(self.payload(profile='mac',curve=m.DEFAULT_CURVE))
        self.assertTrue(m.status()['canRestore'])
        self.assertTrue(m.effective()['input']['touchpad']['accel_profile'].startswith('custom 0.1 '))
        self.assertEqual(m.effective()['input']['touchpad']['sensitivity'],.2)
        self.assertIn('# preserve me',m.MAIN.read_text())
        self.assertIn('[general]\nshow_cheatsheet = false',m.MAIN.read_text())
        m.apply({'revision':m.revision()},restore=True)
        self.assertNotIn('accel_profile',m.effective()['input']['touchpad'])
        m.apply({'revision':m.revision()},restore=True)
        self.assertEqual(m.status()['settings']['profile'],'mac')
        self.assertFalse(m.JOURNAL.exists())
        self.assertTrue(original.startswith('# preserve me'))

    def test_stale_request_cannot_overwrite_external_changes(self):
        payload=self.payload(profile='flat')
        (m.MAIN.parent/'base.toml').write_text('[input.touchpad]\nsensitivity = -0.5\n')
        with self.assertRaisesRegex(ValueError,'Configuration changed'):m.apply(payload)
        self.assertFalse(m.OWNED.exists())

    def test_root_override_rejected_before_live_files_change(self):
        m.MAIN.write_text(m.MAIN.read_text()+'\n[input.touchpad]\naccel_profile = "flat"\n')
        original=m.MAIN.read_text()
        with self.assertRaisesRegex(ValueError,'overridden'):m.apply(self.payload(profile='mac',curve=m.DEFAULT_CURVE))
        self.assertEqual(m.MAIN.read_text(),original)
        self.assertFalse(m.OWNED.exists())
        self.reload.assert_not_called()

    def test_reload_failure_rolls_back_exact_originals(self):
        original=m.MAIN.read_text()
        self.reload.side_effect=[ValueError('simulated reload failure'),None]
        with self.assertRaisesRegex(ValueError,'simulated'):m.apply(self.payload(profile='flat'))
        self.assertEqual(m.MAIN.read_text(),original)
        self.assertFalse(m.OWNED.exists())
        self.assertFalse(m.JOURNAL.exists())

    def test_crash_recovery_and_external_conflict(self):
        before={'main':m.MAIN.read_text(),'owned':None}
        after={'main':m.include_text(before['main']),'owned':m.render({'active':False,'settings':{},'previous':None})}
        m.atomic(m.JOURNAL,json.dumps({'before':before,'after':after}))
        m.atomic(m.OWNED,after['owned']);m.atomic(m.MAIN,after['main'])
        m.MAIN.write_text(m.MAIN.read_text()+'# external\n')
        with self.assertRaisesRegex(ValueError,'Recovery paused'):m.recover()
        self.assertTrue(m.JOURNAL.exists())
        m.MAIN.write_text(after['main']);m.recover()
        self.assertEqual(m.MAIN.read_text(),before['main'])
        self.assertFalse(m.OWNED.exists())

    def test_invalid_input_and_symlink(self):
        for changes in [dict(sensitivity=float('nan')),dict(scroll_factor=.01),dict(tap=1),dict(profile='unknown'),dict(profile='custom',curve=dict(precision=1,start=2,end=1,fast=2))]:
            with self.assertRaises(ValueError):m.validate(self.payload(**changes)['settings'])
        m.OWNED.symlink_to(m.MAIN)
        with self.assertRaises(ValueError):m.status()

    def test_validation_failure_does_not_touch_watched_files(self):
        before=m.MAIN.read_text()
        with patch.object(m,'run',side_effect=ValueError('invalid candidate')):
            with self.assertRaisesRegex(ValueError,'invalid candidate'):m.apply(self.payload(profile='flat'))
        self.assertEqual(m.MAIN.read_text(),before)
        self.assertFalse(m.OWNED.exists())
        self.assertFalse(m.JOURNAL.exists())

    def test_include_edit_preserves_multiline_and_comments(self):
        text='# head\n[include]\nfiles = ["base.toml"] # base\n[include.optional]\nfiles = [\n "extra.toml",\n] # extras\n\n[input.keyboard]\nlayout = "de"\n'
        updated=m.include_text(text)
        self.assertIn('# head',updated);self.assertIn('# base',updated);self.assertIn('# extras',updated)
        self.assertEqual(m.include_text(updated),updated)
        self.assertEqual(m.tomllib.loads(updated)['input']['keyboard']['layout'],'de')

    def test_cli_json_stdin_roundtrip(self):
        import os, shutil
        bindir=self.root/'bin';bindir.mkdir()
        shim=bindir/'umbriel'
        shim.write_text('#!/usr/bin/env python3\nimport os,sys\nif sys.argv[1:]==["msg","config-reload"]: print("ok")\nelse: os.execv('+repr(shutil.which('umbriel'))+', ["umbriel",*sys.argv[1:]])\n')
        shim.chmod(0o700)
        env=dict(os.environ,XDG_CONFIG_HOME=str(self.root),PATH=str(bindir)+os.pathsep+os.environ['PATH'])
        def cli(action,payload=None):
            result=subprocess.run(['python3',str(ROOT/'shell/scripts/touchpad.py'),action],input=json.dumps(payload or {}),text=True,capture_output=True,env=env,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            return json.loads(result.stdout)
        state=cli('status')
        changed=cli('apply',dict(revision=state['revision'],settings=dict(state['settings'],profile='mac',curve=m.DEFAULT_CURVE)))
        self.assertEqual(changed['settings']['profile'],'mac')
        restored=cli('restore',dict(revision=changed['revision']))
        self.assertEqual(restored['settings']['profile'],'system')

    def test_modified_managed_file_is_not_overwritten(self):
        m.apply(self.payload(profile='flat'))
        m.OWNED.write_text(m.OWNED.read_text().replace('accel_profile = "flat"','accel_profile = "adaptive"'))
        with self.assertRaisesRegex(ValueError,'changed externally'):m.status()

if __name__=='__main__':unittest.main()
