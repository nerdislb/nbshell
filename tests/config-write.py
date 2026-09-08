#!/usr/bin/env python3
"""Exercise shared config locks, patch conflicts and the real Quickshell writer."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
WRITER = ROOT / 'shell/scripts/config-write.py'


class ConfigWriteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="config ' writes ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.root/'config'),
                        XDG_STATE_HOME=str(self.root/'state'), QT_QPA_PLATFORM='offscreen',
                        QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
        self.config = self.root/'config/nbshell/config.json'
        self.config.parent.mkdir(parents=True)
        self.config.write_text(json.dumps({'schemaVersion':1,'alpha':0,'beta':0}))

    def patch(self, data):
        return subprocess.run([sys.executable,str(WRITER)],input=json.dumps(data),
                              env=self.env,capture_output=True,text=True,timeout=10)

    def test_independent_concurrent_writers_merge(self):
        workers=[]
        for i in range(16):
            p=subprocess.Popen([sys.executable,str(WRITER)],env=self.env,stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            p.stdin.write(json.dumps({f'key{i}':{'present':False,'value':i}}));p.stdin.close()
            workers.append(p)
        for p in workers:
            self.assertEqual(p.wait(timeout=10),0,p.stdout.read()+p.stderr.read())
            p.stdout.close();p.stderr.close()
        data=json.loads(self.config.read_text())
        for i in range(16):self.assertEqual(data[f'key{i}'],i)
        self.assertEqual(data['alpha'],0)
        self.assertEqual(self.config.stat().st_mode&0o777,0o600)

    def test_conflict_is_atomic_and_idempotent(self):
        self.assertEqual(self.patch({'alpha':{'present':True,'before':0,'value':1}}).returncode,0)
        before=self.config.read_bytes()
        result=self.patch({'alpha':{'present':True,'before':0,'value':2},
                           'beta':{'present':True,'before':0,'value':3}})
        self.assertEqual(result.returncode,1)
        self.assertTrue(json.loads(result.stdout)['conflict'])
        self.assertEqual(before,self.config.read_bytes())
        self.assertEqual(self.patch({'alpha':{'present':True,'before':0,'value':1}}).returncode,0)

    def test_invalid_missing_and_future_config_are_preserved(self):
        for raw in ('{broken','[]','{"schemaVersion":2}','{"schemaVersion":true}', '{"schemaVersion":1,"alpha":NaN}'):
            self.config.write_text(raw)
            self.assertNotEqual(self.patch({'alpha':{'present':False,'value':2}}).returncode,0)
            self.assertEqual(self.config.read_text(),raw)
        self.config.unlink()
        self.assertNotEqual(self.patch({'alpha':{'present':False,'value':2}}).returncode,0)
        self.assertFalse(self.config.exists())

    def test_same_key_concurrent_writers_have_one_winner(self):
        workers=[]
        for value in (1,2):
            p=subprocess.Popen([sys.executable,str(WRITER)],env=self.env,stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            p.stdin.write(json.dumps({'alpha':{'present':True,'before':0,'value':value}}));p.stdin.close()
            workers.append(p)
        codes=[p.wait(timeout=10) for p in workers]
        self.assertEqual(sorted(codes),[0,1])
        for p in workers:p.stdout.close();p.stderr.close()
        self.assertIn(json.loads(self.config.read_text())['alpha'],(1,2))

    def test_migration_uses_the_same_lock(self):
        lock=self.root/'state/nbshell/config-migration.lock';lock.parent.mkdir(parents=True)
        with lock.open('a+b') as held:
            fcntl.flock(held,fcntl.LOCK_EX)
            migration=subprocess.Popen([sys.executable,str(ROOT/'shell/scripts/config-migrations.py'),'apply','--json'],
                                       env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            time.sleep(.15)
            self.assertIsNone(migration.poll())
            fcntl.flock(held,fcntl.LOCK_UN)
        out,err=migration.communicate(timeout=5)
        self.assertEqual(migration.returncode,0,out+err)

    def test_busy_writer_times_out_without_changes(self):
        lock=self.root/'state/nbshell/config-migration.lock';lock.parent.mkdir(parents=True)
        original=self.config.read_bytes()
        with lock.open('a+b') as held:
            fcntl.flock(held,fcntl.LOCK_EX)
            started=time.monotonic()
            result=self.patch({'alpha':{'present':True,'before':0,'value':2}})
            self.assertEqual(result.returncode,1)
            self.assertIn('busy',json.loads(result.stdout)['error'])
            self.assertLess(time.monotonic()-started,8)
        self.assertEqual(self.config.read_bytes(),original)

    def test_bootstrap_records_ledger_and_refuses_missing_existing_state(self):
        self.config.unlink()
        code="import runpy,sys; m=runpy.run_path(sys.argv[1]); m['update_config'](lambda data:dict(data,alpha=1),create=True)"
        result=subprocess.run([sys.executable,'-c',code,str(WRITER)],env=self.env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        ledger=self.root/'state/nbshell/config-migrations.json'
        self.assertTrue(ledger.exists())
        self.config.unlink()
        result=subprocess.run([sys.executable,'-c',code,str(WRITER)],env=self.env,capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.config.exists())

    def test_post_replace_io_failure_is_uncertain_and_replayable(self):
        code="""import runpy,sys
api=runpy.run_path(sys.argv[1])
original=api['M']['atomic_write']
def fail_after_replace(*args):
    original(*args)
    raise OSError('Injected directory sync failure')
api['M']['atomic_write']=fail_after_replace
raise SystemExit(api['main']())
"""
        request={'alpha':{'present':True,'before':0,'value':1}}
        result=subprocess.run([sys.executable,'-c',code,str(WRITER)],input=json.dumps(request),
                              env=self.env,capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertTrue(json.loads(result.stdout)['uncertain'])
        self.assertEqual(json.loads(self.config.read_text())['alpha'],1)
        self.assertEqual(self.patch(request).returncode,0)

    def test_reserved_schema_and_json_types(self):
        self.assertNotEqual(self.patch({'schemaVersion':{'present':True,'before':1,'value':2}}).returncode,0)
        self.assertNotEqual(self.patch({'alpha':{'present':True,'before':False,'value':2}}).returncode,0)
        self.assertEqual(json.loads(self.config.read_text())['alpha'],0)

    def runtime_case(self, conflict, ack_loss=False):
        qs=shutil.which('quickshell') or shutil.which('qs')
        if not qs:self.skipTest('Quickshell unavailable')
        shell=self.root/'shell';(shell/'Common').mkdir(parents=True)
        shutil.copy(ROOT/'shell/Common/Config.qml',shell/'Common/Config.qml')
        (shell/'Common/qmldir').write_text('singleton Config 1.0 Config.qml\n')
        if ack_loss:
            (shell/'scripts').mkdir()
            shutil.copy(ROOT/'shell/scripts/config-migrations.py',shell/'scripts/config-migrations.py')
            shutil.copy(WRITER,shell/'scripts/config-write-base.py')
            (shell/'scripts/config-write.py').write_text("""import json,os,runpy,sys
from pathlib import Path
api=runpy.run_path(str(Path(__file__).with_name('config-write-base.py')))
marker=Path(__file__).with_name('committed')
if not marker.exists():
    api['apply_patch'](json.load(sys.stdin))
    marker.touch()
    os._exit(9)
raise SystemExit(api['main']())
""")
        else:
            (shell/'scripts').symlink_to(ROOT/'shell/scripts',target_is_directory=True)
        ready=self.root/'ready'
        (shell/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
ShellRoot {
 Timer { interval:20; running:true; repeat:true; onTriggered: {
   if (!Config.configValid) return;
   Config.set("alpha",1); Config.set("alpha",2);
   later.start(); stop();
 } }
 Timer { id:later; interval:200; onTriggered: { Config.set("alpha",3); Config.set("queuedOther",42); marker.running=true; } }
 Process { id:marker; command:["python3","-c","from pathlib import Path; Path(" + JSON.stringify(READY) + ").touch()"] }
 Timer { interval:2000; running:true; onTriggered: {
   console.log("CONFIG_RESULT " + JSON.stringify({data:Config.data,error:Config.writeError,saving:Config.saving})); Qt.quit();
 } }
}
'''.replace('READY',json.dumps(str(ready))))
        lock=self.root/'state/nbshell/config-migration.lock';lock.parent.mkdir(parents=True)
        with lock.open('a+b') as held:
            fcntl.flock(held,fcntl.LOCK_EX)
            p=subprocess.Popen([qs,'-p',str(shell)],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                deadline=time.monotonic()+6
                while not ready.exists() and p.poll() is None and time.monotonic()<deadline:time.sleep(.01)
                self.assertTrue(ready.exists(),'QML fixture did not queue writes')
                data=json.loads(self.config.read_text());data['beta']=9
                if conflict:data['alpha']=7
                self.config.write_text(json.dumps(data))
            finally:
                fcntl.flock(held,fcntl.LOCK_UN)
        out,err=p.communicate(timeout=8)
        self.assertEqual(p.returncode,0,out+err)
        self.assertNotIn('ReferenceError',out+err)
        line=next(line.split('CONFIG_RESULT ',1)[1] for line in (out+err).splitlines() if 'CONFIG_RESULT ' in line)
        state=json.loads(line)
        self.assertFalse(state['saving'],out+err)
        self.assertEqual(json.loads(self.config.read_text())['beta'],9)
        self.assertEqual(state['data']['beta'],9)
        self.assertEqual(state['data']['queuedOther'],42,out+err)
        self.assertEqual(state['data']['alpha'],7 if conflict else 3,out+err)
        self.assertEqual(bool(state['error']),conflict,out+err)

    def test_real_qml_inflight_queue_merges_external_change(self):self.runtime_case(False)
    def test_real_qml_conflict_preserves_unrelated_queue(self):self.runtime_case(True)
    def test_real_qml_lost_commit_reply_is_replayed_safely(self):self.runtime_case(False,True)


if __name__=='__main__':unittest.main()
