"""Speed-test conversion, bounded failures and real process-tree cancellation."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('speed_adapter', ROOT / 'shell/scripts/speedtest.py')
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)


def alive(pid):
    try:
        return Path(f'/proc/{pid}/stat').read_text().split(') ')[1].split()[0] != 'Z'
    except FileNotFoundError:
        return False


class SpeedTest(unittest.TestCase):
    def test_both_backends_and_units(self):
        self.assertEqual(adapter.normalized({'download':94200000, 'upload':38100000, 'ping':12.4,
                          'server':{'name':'City','sponsor':'ISP'}}),
                         dict(ok=True, down=94.2, up=38.1, ping=12.4, server='City, ISP'))
        self.assertEqual(adapter.normalized({'download':{'bandwidth':12500000},'upload':{'bandwidth':6250000},
                          'ping':{'latency':4.2},'server':{'location':'City','name':'ISP'}},True),
                         dict(ok=True, down=100, up=50, ping=4.2, server='City, ISP'))

    def test_untrusted_invalid_measurements(self):
        for value in [-1, float('nan'), float('inf'), 'broken', {}]:
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                adapter.normalized({'download':value})

    def test_missing_client(self):
        with patch.object(adapter.shutil, 'which', return_value=None):
            self.assertFalse(adapter.measure()['ok'])

    def test_client_failure_and_malformed_output(self):
        with tempfile.TemporaryDirectory() as directory:
            client=Path(directory)/'speedtest-cli'
            for body in ['exit 1', 'printf broken', 'printf null']:
                client.write_text('#!/bin/sh\n'+body+'\n');client.chmod(0o755)
                with patch.object(adapter.shutil, 'which', return_value=str(client)):
                    self.assertFalse(adapter.measure()['ok'])

    def fixture(self, directory):
        pids=Path(directory)/'pids'
        client=Path(directory)/'speedtest-cli'
        client.write_text('#!/usr/bin/python3\n'+f'''
import os, signal, subprocess, time
from pathlib import Path
worker=subprocess.Popen(['/usr/bin/python3','-c','import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(300)'], stdout=subprocess.DEVNULL)
Path({str(pids)!r}).write_text(str(os.getpid())+' '+str(worker.pid))
while True: time.sleep(.02)
''')
        client.chmod(0o755)
        return client,pids

    def test_timeout_kills_child_and_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            client,pids=self.fixture(directory)
            with patch.object(adapter.shutil, 'which', return_value=str(client)):
                result=adapter.measure(timeout=.3)
            self.assertIn('timed out',result['grund'])
            for pid in map(int,pids.read_text().split()):
                deadline=time.monotonic()+2
                while alive(pid) and time.monotonic()<deadline: time.sleep(.02)
                self.assertFalse(alive(pid),pid)

    def test_dismissal_kills_child_and_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            _,pids=self.fixture(directory)
            env=dict(os.environ,PATH=directory+':/usr/bin:/bin')
            proc=subprocess.Popen(['/usr/bin/python3',str(ROOT/'shell/scripts/speedtest.py')],env=env,stdout=subprocess.PIPE,text=True)
            try:
                deadline=time.monotonic()+3
                while not pids.exists() and time.monotonic()<deadline: time.sleep(.02)
                self.assertTrue(pids.exists())
                proc.send_signal(signal.SIGTERM)
                output,_=proc.communicate(timeout=3)
                self.assertEqual(output,'')
                self.assertEqual(proc.returncode,143)
                for pid in map(int,pids.read_text().split()):
                    deadline=time.monotonic()+2
                    while alive(pid) and time.monotonic()<deadline: time.sleep(.02)
                    self.assertFalse(alive(pid),pid)
            finally:
                if proc.poll() is None:
                    proc.terminate();proc.wait(timeout=3)


if __name__ == '__main__': unittest.main()
