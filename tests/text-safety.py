#!/usr/bin/env python3
"""Real Qt network regression with an AutoText positive control, loopback only."""
import http.server, json, os, shutil, subprocess, tempfile, threading
from pathlib import Path
qs = shutil.which('quickshell') or shutil.which('qs')
if not qs:
 print('Text safety runtime: SKIP (Quickshell unavailable; static contract runs separately)')
 raise SystemExit(0)
hits=[]
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  hits.append(self.path); self.send_response(204); self.end_headers()
 def log_message(self,*args): pass
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
results={}
try:
 for mode in ('default','auto-control'):
  with tempfile.TemporaryDirectory() as temporary:
   root=Path(temporary); (root/'Widgets').mkdir(); (root/'Common').mkdir()
   shutil.copy(Path(__file__).resolve().parents[1] / 'shell/Widgets/Line.qml',root/'Widgets/Line.qml')
   (root/'Widgets/qmldir').write_text('Line 1.0 Line.qml\n')
   (root/'Common/qmldir').write_text('singleton Theme 1.0 Theme.qml\n')
   (root/'Common/Theme.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property color fg: "white"; property string fontFamily: "monospace"; property int fontSize: 14 }')
   payload=f'<img src="http://127.0.0.1:{server.server_port}/{mode}">'
   format='textFormat: Text.AutoText;' if mode=='auto-control' else ''
   (root/'shell.qml').write_text('import QtQuick\nimport QtQuick.Window\nimport Quickshell\nimport qs.Widgets\nShellRoot { Window {visible: true; width: 300; height: 100; Line { width: 280; maximumLineCount: 2; elide: Text.ElideRight; '+format+' text: '+json.dumps(payload)+' } } Timer { interval: 1000; running:true; onTriggered: Qt.quit() } }')
   result=subprocess.run([qs,'-p',str(root)],env=dict(os.environ,QT_QPA_PLATFORM='offscreen'),text=True,capture_output=True,timeout=5)
   assert result.returncode==0,result.stdout+result.stderr
   results[mode]={'loopback_requests':hits.count('/'+mode),'returncode':result.returncode}
finally:
 server.shutdown(); server.server_close()
assert results['auto-control']['loopback_requests']>0 and results['default']['loopback_requests']==0,results
print(json.dumps(results,indent=2))
