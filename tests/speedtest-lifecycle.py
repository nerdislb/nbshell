"""Private native gauges, batch results, focus and process-tree lifecycle checks."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    client=Path('/test-bin/speedtest-cli')
    client.write_text('''#!/usr/bin/python3
import json, os, subprocess, time
from pathlib import Path
spec=json.loads(Path('/work/speed-fixture.json').read_text())
worker=None
if spec['mode']=='hold':
    worker=subprocess.Popen(['/usr/bin/python3','-c','import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(300)'],stdout=subprocess.DEVNULL)
with Path('/work/speed-runs.jsonl').open('a') as f:
    f.write(json.dumps({'pid':os.getpid(),'worker':worker.pid if worker else None,'mode':spec['mode']})+'\\n')
if spec['mode']=='hold':
    gate=Path('/work/release-'+str(os.getpid())+'.json')
    while not gate.exists():time.sleep(.02)
    print(gate.read_text())
elif spec['mode']=='failure':raise SystemExit(3)
elif spec['mode']=='malformed':print('not json')
else:print(json.dumps(spec['payload']))
''');client.chmod(0o755)
    Path('/work/speed-fixture.json').write_text(json.dumps({'mode':'hold'}))
    p=shell/'Common/Runtime.qml';s=p.read_text();i=s.index('{');s=s[:i+1]+'\n    property bool speedTestMounted: false\n'+s[i+1:];p.write_text(s)
    p=shell/'Net/SpeedWindow.qml';s=p.read_text().replace('        id: dial', '        id: dial\n        readonly property bool testLabelsFit: readout.y+readout.height<=directionLabel.y',1).replace('    id: root','''    id: root
    QtObject { Component.onCompleted: Runtime.speedTestMounted=true; Component.onDestruction: Runtime.speedTestMounted=false }''',1);end=s.rfind('}')
    s=s[:end]+'''
    function testRect(item) {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
    IpcHandler {
        target:"speedProbe"
        function state():string {
            const f=keys.Window.window.activeFocusItem;
            return JSON.stringify({running:root.running,cancelled:root.cancelled,valid:root.valid,error:root.error,
                scale:root.fullScale,persisted:Config.value("speedScale",100),result:root.result,proc:proc.processId,
                enabled:retry.enabled,focus:f?.accessibleName||"",inputFocused:input.activeFocus,
                box:root.testRect(box),retry:root.testRect(retry),close:root.testRect(closeButton),
                viewport:root.testRect(viewport),contentHeight:viewport.contentHeight,scroll:viewport.contentY,
                facts:facts.text,title:title.text,shown:downDial.shown,diameter:downDial.diameter,
                labelsFit:downDial.testLabelsFit && upDial.testLabelsFit,reduced:Theme.reducedMotion,accent:root.gaugeAccent.toString()});
        }
        function accessibleRetry():void {retry.Accessible.pressAction();}
        function accessibleClose():void {closeButton.Accessible.pressAction();}
        function focusInput():void {input.forceActiveFocus();}
    }
'''+s[end:];p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}');s=s[:end]+'''
    IpcHandler {
        target:"speedFixture"
        function state():string {return JSON.stringify({open:Runtime.speedOpen,mounted:Runtime.speedTestMounted});}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('speedProbe','state'))
    def service():return json.loads(ipc('speedFixture','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/speed-results.json').write_text(json.dumps(results,indent=2))
        if not ok:print('FAILED STATE',state() if service()['mounted'] else service(),flush=True)
        assert ok,name
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','180000'],'speed-seat.log')
    def key(code):pointer('pause',40,'tap',code,'pause',100)
    def shot(name):time.sleep(.15);run(['grim','/work/speed-'+name+'.png'])
    def click(rect):pointer('move',round((rect['x']+rect['w']/2)*args.scale),round((rect['y']+rect['h']/2)*args.scale),'click',272,'pause',100)
    def runs():
        p=Path('/work/speed-runs.jsonl');return [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []
    def mode(value,payload=None):Path('/work/speed-fixture.json').write_text(json.dumps({'mode':value,'payload':payload}))
    def raw(down=94.2,up=38.1,ping=12.4,server='Fixture City, ISP'):
        return {'download':down*1e6,'upload':up*1e6,'ping':ping,'server':{'name':server}}
    def release(payload):Path('/work/release-'+str(runs()[-1]['pid'])+'.json').write_text(json.dumps(payload))
    def alive(pid):
        if not pid:return False
        try:return Path(f'/proc/{pid}/stat').read_text().split(') ')[1].split()[0]!='Z'
        except FileNotFoundError:return False
    def tree_gone(entry):return not alive(entry['pid']) and not alive(entry['worker'])
    def closed():return not service()['mounted'] and not service()['open']
    def open_menu():
        n=len(runs());ipc('net','speed');wait(lambda:service()['mounted'] and len(runs())==n+1,'speed starts');time.sleep(.15)
    def finished():wait(lambda:not state()['running'],'measurement finishes');time.sleep(.35)
    def fits():
        b=state()['box'];return b['x']>=0 and b['y']>=0 and b['x']+b['w']<=args.width/args.scale and b['y']+b['h']<=args.height/args.scale
    def control_visible(name):
        s=state();r=s[name];v=s['viewport'];return r['y']>=v['y'] and r['y']+r['h']<=v['y']+v['h']+1
    target=Path('/work/speed-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Speed focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'speed-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus');open_menu()
    record('open starts one real isolated client',len(runs())==1 and state()['running'])
    record('batch measurement shows unknown instead of fabricated values',not state()['valid'] and state()['shown']==0 and not state()['enabled']);shot('running')
    record('gauge cluster fits current output',fits() and state()['diameter']>100)
    record('readout units and direction labels do not overlap',state()['labelsFit'])
    record('Reduced Motion follows configuration',state()['reduced']==(args.motion=='reduced'))
    key(28);key(57);ipc('speedProbe','accessibleRetry');record('all retry paths suppress concurrent runs',len(runs())==1)
    key(15);record('Tab skips disabled retry and focuses Close',state()['focus']=='Close speed test');shot('running-focus')
    first=runs()[-1];release(raw());finished();wait(lambda:tree_gone(first),'completed helper tree is gone')
    record('native conversion exposes measured download upload and server',state()['result']['down']==94.2 and state()['result']['up']==38.1 and state()['title']=='Fixture City, ISP')
    record('ping and persisted scale extras remain', '12.4 ms' in state()['facts'] and state()['scale']==100 and state()['persisted']==100);shot('result')
    ipc('speedProbe','focusInput');key(15);record('Tab reaches retry after completion',state()['focus']=='Measure again');shot('retry-focus')
    mode('hold');key(57);wait(lambda:len(runs())==2,'Space starts retry')
    record('starting focused retry returns focus before disabling it',state()['inputFocused'] and state()['running'])
    release(raw(536.6,240.1));finished();record('scale expands to next 50 and persists',state()['scale']==550 and state()['persisted']==550);shot('expanded')
    mode('success',raw(0,0,1800000));click(state()['retry']);wait(lambda:len(runs())==3,'pointer retry');finished()
    record('zero readings retained and implausible ping hidden',state()['valid'] and state()['result']['down']==0 and '1800000' not in state()['facts'])
    record('scale never shrinks for slower results',state()['scale']==550);shot('zero')
    mode('failure');ipc('speedProbe','accessibleRetry');wait(lambda:len(runs())==4,'accessible retry');finished()
    record('failed client exposes retryable error without stale numbers',bool(state()['error']) and not state()['valid'] and state()['enabled']);shot('error')
    mode('malformed');key(28);wait(lambda:len(runs())==5,'Enter retry');finished();record('malformed backend response becomes readable error','invalid response' in state()['error'])
    mode('success',raw());ipc('speedProbe','focusInput');pointer('key-press',28,'pause',1100,'key-release',28,'pause',100);finished()
    record('held Enter starts only one fresh run',len(runs())==6)
    mode('success',raw(server='<b>Literal server</b> '+'Long provider name '*110));key(57);wait(lambda:len(runs())==7,'long server');finished()
    record('long server retained literally with bounded viewport',state()['title'].startswith('<b>') and state()['contentHeight']>state()['viewport']['h'] and fits());shot('long')
    key(15);record('Tab reveals retry through long content',state()['focus']=='Measure again' and control_visible('retry'))
    key(15);record('Tab reveals Close through long content',state()['focus']=='Close speed test' and control_visible('close'));shot('long-focus')
    key(1);wait(closed,'Escape closes');key(30)
    record('Escape restores prior application focus',underlying()['focused'] and underlying()['keys']==[65])
    mode('hold');open_menu();record('reopening restores persistent scale',state()['scale']==550)
    entry=runs()[-1];key(1);wait(closed,'running Escape cleanup');wait(lambda:tree_gone(entry),'running child group killed')
    record('Escape cancels client and TERM-ignoring worker',tree_gone(entry))
    open_menu();entry=runs()[-1];ipc('speedProbe','accessibleClose');wait(closed,'accessible Close');wait(lambda:tree_gone(entry),'accessible tree killed')
    record('accessible Close cancels actual backend tree',tree_gone(entry))
    open_menu();entry=runs()[-1];pointer('move',2,2,'click',272,'pause',100);wait(closed,'outside close');wait(lambda:tree_gone(entry),'outside tree killed')
    record('outside click cancels actual backend tree',tree_gone(entry))
    open_menu();entry=runs()[-1];n=len(runs());ipc('net','speed');ipc('net','speed');wait(lambda:len(runs())==n+1,'rapid reopen queued');wait(lambda:tree_gone(entry),'old reopen tree killed')
    record('rapid reopen waits for old client teardown',service()['open'] and state()['running'] and tree_gone(entry))
    release(raw(125,25));finished();record('rapid reopen accepts only fresh result',state()['result']['down']==125)
    mode('hold');key(28);wait(lambda:state()['running'],'final hold');entry=runs()[-1];click(state()['close']);wait(closed,'pointer Close');wait(lambda:tree_gone(entry),'pointer tree killed')
    record('pointer Close uses same cancellation path',tree_gone(entry))
    record('all fixture processes are gone',all(tree_gone(e) for e in runs()))
    log=Path('/work/shell.log').read_text()
    record('no QML type or binding errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
