"""Capture UI and deferred dispatch on a private Wayland seat, no real captures."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Services/CaptureService.qml';s=p.read_text()
    s=s.replace('    id: root','''    id: root
    property var testCalls: []
    property var testWindows: []
    property bool testMounted: false
    function testRecord(action, windowId) {
        testCalls=testCalls.concat([{action:action,windowId:windowId ?? null,
            open:Runtime.captureOpen,mounted:testMounted,pending:pendingAction}]);
    }''',1)
    # Retain the real service-owned scheduling timer; replace effects only.
    s=re.sub(r'(    function runAction\(action\) \{).*?\n    }',r'\1\n        testRecord(action,null);\n    }',s,flags=re.S)
    s=re.sub(r'(    function shootWindow\(windowId\) \{).*?\n    }',r'\1\n        if(!testWindows.some(w=>w.id===windowId))return false;\n        testRecord("window",windowId);return true;\n    }',s,flags=re.S)
    p.write_text(s)
    p=shell/'Capture/CaptureMenu.qml';s=p.read_text().replace('Compositor.windows','CaptureService.testWindows')
    s=s.replace('    id: root','''    id: root
    QtObject { Component.onCompleted: CaptureService.testMounted=true }
    Component.onDestruction: CaptureService.testMounted=false''',1)
    end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    function testRect(item) {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
    IpcHandler {
        target:"captureProbe"
        function state():string {
            const row=rows.itemAt(root.selected),f=keys.Window.window.activeFocusItem;
            return JSON.stringify({key:root.selectedKey,index:root.selected,windowMode:root.windowMode,
                actions:root.shownActions.map(a=>({id:a.id,label:a.label,key:a.key})),
                focus:f?.accessibleName||f?.Accessible.name||"",box:root.testRect(box),
                row:row?root.testRect(row):{},list:root.testRect(list),footer:root.testRect(footer),
                scroll:list.contentY,recording:CaptureService.recording,
                rowVisible:!!row && row.y>=list.contentY-1 && row.y+row.height<=list.contentY+list.height+1});
        }
        function select(id:string):void {root.selectedKey=id;root.focusSelection();}
        function rect(id:string):string {const i=root.shownActions.findIndex(a=>a.id===id);return JSON.stringify(root.testRect(rows.itemAt(i)));}
        function activate(id:string):void {root.activate(id);}
        function repeatEnter():void {const e={key:Qt.Key_Return,isAutoRepeat:true,accepted:false};rows.itemAt(root.selected)?.activateFromKey(e);}
    }
'''+s[end:];p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"captureFixture"
        function setup():void {
            CaptureService.testCalls=[];
            CaptureService.testWindows=Array.from({length:35},(_,i)=>({id:100+i,
                title:(i===0 ? "00 A literal <b>window</b> " + "long window title ".repeat(12) : String(i).padStart(2,"0")+" Window title"),
                app_id:"org.fixture.Application"}));
        }
        function state():string {return JSON.stringify({calls:CaptureService.testCalls,open:Runtime.captureOpen,mounted:CaptureService.testMounted,pending:CaptureService.pendingAction});}
        function prepend():void {CaptureService.testWindows=[{id:99,title:"00 A concurrent window",app_id:"fixture"}].concat(CaptureService.testWindows);}
        function remove(id:int):void {CaptureService.testWindows=CaptureService.testWindows.filter(w=>w.id!==id);}
        function empty():void {CaptureService.testWindows=[];}
        function recording(value:bool):void {CaptureService.recording=value;}
        function scheduleWindow(id:int):void {CaptureService.schedule("window",id);}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('captureProbe','state'))
    def service():return json.loads(ipc('captureFixture','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/capture-results.json').write_text(json.dumps(results,indent=2))
        assert ok,(name,service())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','120000'],'capture-seat.log')
    def key(code,mod=None):pointer('pause',50,*(['mod',mod] if mod else []),'tap',code,*(['mod','none'] if mod else []),'pause',100)
    def shot(name):time.sleep(.15);run(['grim','/work/capture-'+name+'.png'])
    def open_menu(windows=False):
        ipc('capture','window' if windows else 'menu');wait(lambda:service()['mounted'],'capture mapped');time.sleep(.12)
    def closed():return not service()['mounted'] and not service()['open']
    def click(id):
        ipc('captureProbe','select',id);time.sleep(.1);p=json.loads(ipc('captureProbe','rect',id))
        pointer('move',round((p['x']+p['w']/2)*args.scale),round((p['y']+p['h']/2)*args.scale),'pause',100,'click',272,'pause',100)
    target=Path('/work/capture-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Capture focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'capture-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus')
    ipc('captureFixture','setup');open_menu()
    s=state();b=s['box'];f=s['footer']
    record('all eleven actions preserved',len(s['actions'])==11)
    record('initial focus and selection agree',s['key']=='screen' and s['focus']=='Screen')
    record('card and footer fit output',b['x']>=0 and b['y']>=0 and b['x']+b['w']<=args.width/args.scale and b['y']+b['h']<=args.height/args.scale and f['y']+f['h']<=b['y']+b['h'])
    shot('initial')
    p=json.loads(ipc('captureProbe','rect','window'))
    x=round((p['x']+p['w']/2)*args.scale);y=round((p['y']+p['h']/2)*args.scale)
    pointer('move',x,y,'pause',100,'move',x+4,y,'pause',100)
    record('physical hover aligns keyboard activation target',state()['key']=='window' and state()['focus']=='Window')
    key(28);record('Enter after hover opens that window submenu',state()['windowMode'] and service()['calls']==[])
    key(1);ipc('captureProbe','select','screen');key(15)
    record('Tab follows visual row order',state()['key']=='window' and state()['focus']=='Window')
    key(107);record('End reaches final action and scrolls',state()['key']=='open' and state()['rowVisible'] and state()['scroll']>0);shot('last-action')
    key(108);record('Down wraps to first action',state()['key']=='screen' and state()['rowVisible'])
    key(109);record('PageDown navigates without activation',state()['key']=='record' and service()['calls']==[])
    ipc('captureProbe','repeatEnter');record('autorepeat activation is ignored',service()['calls']==[] and service()['open'])
    key(1);wait(closed,'Escape closes');key(30)
    record('Escape restores application focus',underlying()['focused'] and underlying()['keys']==[65])
    open_menu();key(1,'ctrl')
    # Escape is an explicit global dismissal, regardless of modifiers.
    wait(closed,'modified Escape closes')
    open_menu();key(33);time.sleep(.15)
    s=state();record('F opens window selector without capture',s['windowMode'] and len(s['actions'])==35 and service()['calls']==[])
    record('window selector stays on output',s['box']['x']>=0 and s['box']['x']+s['box']['w']<=args.width/args.scale and s['rowVisible'])
    shot('windows');key(107)
    record('all windows reachable and focused row visible',state()['key']=='window-134' and state()['rowVisible'])
    shot('last-window');ipc('captureFixture','prepend');time.sleep(.2)
    record('new window preserves selected target and focus',state()['key']=='window-134' and state()['focus']=='34 Window title')
    key(28);wait(closed,'window capture closes menu');wait(lambda:len(service()['calls'])==1,'window capture dispatched')
    record('window capture dispatched after lazy menu destroyed',service()['calls']==[dict(action='window',windowId=134,open=False,mounted=False,pending='')])
    open_menu(True);ipc('captureProbe','select','window-120');ipc('captureFixture','remove','120');time.sleep(.15)
    ipc('captureProbe','activate','window-120')
    record('removed window cannot activate through stale key',service()['open'] and len(service()['calls'])==1)
    key(1);record('Escape returns to capture actions',not state()['windowMode'] and state()['key']=='window')
    key(106);record('Right opens only window submenu',state()['windowMode'])
    key(105);record('Left returns without capturing',not state()['windowMode'] and len(service()['calls'])==1)
    # The permanent IPC window entry must also work while the menu is already open.
    ipc('capture','window');time.sleep(.15);record('window IPC switches an already-open menu',state()['windowMode'])
    ipc('captureFixture','empty');time.sleep(.2)
    record('empty window list clears stale selection',state()['key']=='' and state()['focus']=='Back to capture actions');shot('empty')
    key(28);record('empty selector offers keyboard back',not state()['windowMode'] and service()['open'])
    key(1);wait(closed,'close after empty')
    ipc('captureFixture','scheduleWindow','777');time.sleep(.4)
    record('window gone during dispatch delay is not captured',len(service()['calls'])==1)
    ipc('captureFixture','setup');open_menu();ipc('captureFixture','recording','true');time.sleep(.2)
    record('recording state updates action label',any(a['label']=='Stop recording' for a in state()['actions']));shot('recording')
    key(1);wait(closed,'close recording state');ipc('captureFixture','recording','false')
    # All existing keyboard shortcuts go through the real delayed service path.
    shortcuts=[('screen',48),('region',30),('ocr',20),('qr',16),('dictate',32),('record',47),('trim',46),('stream',31),('edit',18),('open',24)]
    for i,(action,code) in enumerate(shortcuts):
        open_menu();key(code);wait(closed,'shortcut closes '+action);wait(lambda:len(service()['calls'])==i+1,'dispatch '+action)
        call=service()['calls'][-1]
        record('shortcut '+action+' dispatches once after unmap',call==dict(action=action,windowId=None,open=False,mounted=False,pending=''))
    open_menu();ipc('captureFixture','setup');click('window');time.sleep(.55);click('window-100')
    wait(closed,'pointer window closes');wait(lambda:len(service()['calls'])==1,'pointer window dispatched')
    record('pointer window choice uses exact target once',service()['calls'][0]==dict(action='window',windowId=100,open=False,mounted=False,pending=''))
    open_menu();pointer('move',2,2,'click',272,'pause',100);wait(closed,'outside closes')
    record('outside click does not capture',len(service()['calls'])==1)
    log=Path('/work/shell.log').read_text()
    record('no QML binding or type errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
