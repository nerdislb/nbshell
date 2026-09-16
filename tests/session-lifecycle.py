"""Native session-menu safety/interaction proof; no real session operations."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Services/Session.qml';s=p.read_text()
    s=s.replace('    id: root','''    id: root
    property var testCalls: []
    property bool testMounted: false''',1)
    # Replace the complete effects boundary, not menu logic or confirmation timers.
    s=re.sub(r'    function run\(id\) \{.*?\n    }','''    function run(id) {
        testCalls=testCalls.concat([{id:id,open:Runtime.powerOpen}]);
        return true;
    }''',s,flags=re.S)
    p.write_text(s)
    p=shell/'Power/PowerMenu.qml';s=p.read_text()
    s=s.replace('    id: root','''    id: root
    QtObject { Component.onCompleted: Session.testMounted=true }
    Component.onDestruction: Session.testMounted=false''',1)
    end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    function testRect(item) {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
    IpcHandler {
        target:"sessionProbe"
        function state():string {
            const row=rows.itemAt(root.selected),f=keys.Window.window.activeFocusItem;
            return JSON.stringify({key:root.selectedKey,armed:root.confirmKey,
                actions:root.actions,focus:f?.accessibleName||"",box:root.testRect(box),
                row:row?root.testRect(row):{},list:root.testRect(list),footer:root.testRect(footer),
                scroll:list.contentY,
                rowVisible:!!row && row.y>=list.contentY-1 && row.y+row.height<=list.contentY+list.height+1});
        }
        function rect(id:string):string {const i=root.actions.findIndex(a=>a.id===id);return JSON.stringify(root.testRect(rows.itemAt(i)));}
        function repeatEnter():void {rows.itemAt(root.selected).activateFromKey({isAutoRepeat:true,accepted:false});}
        function repeatShortcut():void {root.shortcut({isAutoRepeat:true,modifiers:Qt.NoModifier,text:root.actions[root.selected].key,accepted:false});}
        function activate(id:string):void {root.activate(id);}
        function accessiblePress():void {rows.itemAt(root.selected).Accessible.pressAction();}
    }
'''+s[end:];p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"sessionFixture"
        function state():string {return JSON.stringify({calls:Session.testCalls,open:Runtime.powerOpen,mounted:Session.testMounted});}
        function reset():void {Session.testCalls=[];}
        function longLabel():void {Session.actions=Session.actions.map(a=>Object.assign({},a,{label:a.id==="poweroff"?"Power off this device with a very long literal <b>label</b>":a.label}));}
    }
'''+s[end:]
    # Session.actions is readonly in production; only fixture can mutate labels.
    p.write_text(s)
    p=shell/'Services/Session.qml';p.write_text(p.read_text().replace('readonly property var actions:', 'property var actions:'))


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('sessionProbe','state'))
    def service():return json.loads(ipc('sessionFixture','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/session-results.json').write_text(json.dumps(results,indent=2))
        assert ok,(name,service())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','120000'],'session-seat.log')
    def key(code,mod=None):pointer('pause',50,*(['mod',mod] if mod else []),'tap',code,*(['mod','none'] if mod else []),'pause',100)
    def shot(name):time.sleep(.15);run(['grim','/work/session-'+name+'.png'])
    def open_menu():
        ipc('power','menu');wait(lambda:service()['mounted'],'session mapped');time.sleep(.12)
    def closed():return not service()['mounted'] and not service()['open']
    def hover(id):
        p=json.loads(ipc('sessionProbe','rect',id))
        pointer('move',round((p['x']+p['w']/2)*args.scale),round((p['y']+p['h']/2)*args.scale),'pause',100,'move',round((p['x']+p['w']/2)*args.scale)+4,round((p['y']+p['h']/2)*args.scale),'pause',100)
    target=Path('/work/session-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Session focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'session-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus')
    open_menu();s=state();b=s['box'];f=s['footer']
    record('all six actions and original shortcuts preserved',[(a['id'],a['key']) for a in s['actions']]==[('lock','s'),('logout','a'),('suspend','b'),('hibernate','r'),('reboot','n'),('poweroff','x')])
    record('initial focus agrees with safe unarmed selection',s['key']=='lock' and s['focus']=='Lock' and s['armed']=='')
    record('card and footer fit output',b['x']>=0 and b['y']>=0 and b['x']+b['w']<=args.width/args.scale and b['y']+b['h']<=args.height/args.scale and f['y']+f['h']<=b['y']+b['h'])
    shot('initial');key(28)
    record('first Enter only arms',state()['armed']=='lock' and service()['calls']==[])
    record('arming does not move card or footer',state()['box']==b and state()['footer']==f)
    ipc('sessionProbe','repeatEnter');ipc('sessionProbe','repeatShortcut')
    record('autorepeat cannot confirm via Enter or shortcut',state()['armed']=='lock' and service()['calls']==[])
    for code,name in [(28,'Enter'),(31,'S shortcut')]:
        key(15);key(15,'shift')
        pointer('key-press',code,'pause',1100,'key-release',code,'pause',100)
        record('held physical '+name+' cannot confirm',service()['open'] and service()['calls']==[] and state()['armed']=='lock')
    key(15);record('Tab changes target and disarms',state()['key']=='logout' and state()['armed']=='')
    key(15,'shift');record('Shift Tab returns without activation',state()['key']=='lock' and service()['calls']==[])
    key(107);record('End reaches last action visibly',state()['key']=='poweroff' and state()['rowVisible']);shot('last')
    key(28);shot('confirm');record('confirmation names the action',state()['focus']=='Confirm Power off')
    key(108);record('Down wraps and disarms',state()['key']=='lock' and state()['armed']=='')
    key(109);record('PageDown reaches final action without running',state()['key']=='poweroff' and service()['calls']==[])
    key(102);record('Home restores first visible action',state()['key']=='lock' and state()['rowVisible'])
    key(28);time.sleep(3.6)
    record('real confirmation timeout disarms',state()['armed']=='' and service()['calls']==[])
    key(28);key(1);wait(closed,'Escape closes armed menu');key(30)
    record('Escape cancels and restores application focus',service()['calls']==[] and underlying()['focused'] and underlying()['keys']==[65])
    open_menu();record('reopen has no stale confirmation',state()['armed']=='' and state()['key']=='lock')
    key(45,'ctrl');record('modified shortcut cannot arm',state()['armed']=='' and service()['calls']==[])
    ipc('sessionProbe','activate','invalid');record('unknown action rejected',state()['armed']=='' and service()['calls']==[])
    hover('logout');record('physical hover aligns focus and selection',state()['key']=='logout' and state()['focus']=='Log out')
    key(28);record('Enter after hover arms exact target',state()['armed']=='logout' and service()['calls']==[])
    hover('suspend');record('pointer target change cancels old confirmation',state()['key']=='suspend' and state()['armed']=='')
    pointer('click',272,'pause',100);record('first pointer click only arms',state()['armed']=='suspend' and service()['calls']==[])
    pointer('click',272,'pause',100);wait(closed,'pointer confirms')
    record('second pointer click dispatches exact action once after close request',service()['calls']==[dict(id='suspend',open=False)])
    ipc('sessionFixture','reset')
    for action,code in [('lock',31),('logout',30),('suspend',48),('hibernate',19),('reboot',49),('poweroff',45)]:
        open_menu();key(code)
        record('shortcut '+action+' requires confirmation',state()['armed']==action and service()['calls']==[])
        ipc('sessionProbe','repeatShortcut');key(code);wait(closed,'confirmed '+action)
        record('shortcut '+action+' dispatches exactly once',service()['calls']==[dict(id=action,open=False)])
        ipc('sessionFixture','reset')
    open_menu();key(57);record('Space arms through shared path',state()['armed']=='lock' and service()['calls']==[])
    key(57);wait(closed,'Space confirms');record('Space confirms once',service()['calls']==[dict(id='lock',open=False)])
    ipc('sessionFixture','reset');open_menu();ipc('sessionProbe','accessiblePress')
    record('accessibility activation first arms',state()['armed']=='lock' and service()['calls']==[])
    ipc('sessionProbe','accessiblePress');wait(closed,'accessible confirms')
    record('accessibility confirms through same path',service()['calls']==[dict(id='lock',open=False)])
    ipc('sessionFixture','reset');open_menu();key(28)
    pointer('move',2,2,'click',272,'pause',100);wait(closed,'outside closes')
    record('outside click cancels armed action',service()['calls']==[])
    open_menu();key(28);ipc('power','menu');wait(closed,'IPC close');open_menu()
    record('IPC close/reopen clears armed state',state()['armed']=='' and service()['calls']==[])
    ipc('sessionFixture','longLabel');time.sleep(.15);key(107);shot('long-label')
    record('long literal label stays reachable with full accessible name',state()['focus']=='Power off this device with a very long literal <b>label</b>' and state()['rowVisible'])
    key(1);wait(closed,'final close')
    log=Path('/work/shell.log').read_text()
    record('no QML binding or type errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
