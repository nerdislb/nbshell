"""Full center, real native input and Notify service, private fixtures only."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    p = shell / 'Services/Notify.qml'
    s = p.read_text().replace('id: root', 'id: root\n    property var testActions: []', 1)
    s = re.sub(r'(    function focus\(entry\) \{).*?\n    }', r'\1\n        testActions = testActions.concat(["focus:"+entry.key]); return true;\n    }', s, flags=re.S)
    p.write_text(s)
    p = shell / 'Notifications/NotificationCenter.qml'
    s = p.read_text(); end = s.rfind('}')
    s = 'import Quickshell.Io\n' + s[:end] + '''
    function testFind(item,name) {
        if(item.visible && item.enabled && item.accessibleName===name)return item;
        for(const child of item.children ?? []) {const found=testFind(child,name);if(found)return found;}
        return null;
    }
    IpcHandler {
        target:"centerProbe"
        function rect(item:var):var {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
        function state():string {
            const f=keys.Window.window.activeFocusItem,card=notificationCards.itemAt(root.selected);
            return JSON.stringify({focus:f?.accessibleName||f?.Accessible.name||"",rect:f?rect(f):{},
                box:rect(box),footer:rect(footer),list:rect(flick),scroll:flick.contentY,
                card:card?rect(card):{},count:Notify.count,rows:root.shown.length,
                key:root.selectedKey,query:root.query,armed:root.clearArmed,dnd:Notify.dnd,
                clearEnabled:clearButton.enabled,actions:Notify.testActions,
                cardFits:card ? card.height <= flick.height : true});
        }
        function setup():void {
            Notify.testActions=[];
            Notify.history=Array.from({length:30},(_,i)=>({key:"fixture-"+i,
                appName:i===0 ? "A long application name for truncation safety" : "Fixture app",
                summary:i===0 ? "A literal <b>title</b> and a long summary for wrapping" : "Notification "+i,
                body:i===0 ? "Long plain notification body. ".repeat(80) : "Notification details and useful context.",
                time:new Date(Date.now()-i*3600000),count:i===0 ? 3 : 1,urgency:i===1 ? 2 : 1,
                appIcon:i===0 ? "https://example.invalid/no-network.png" : "dialog-information",
                notification:i===0 ? {actions:[{identifier:"default",text:"Open",invoke:()=>{Notify.testActions=Notify.testActions.concat(["default"]);}},
                    {identifier:"custom",text:"A very long custom action label ".repeat(8),invoke:()=>{Notify.testActions=Notify.testActions.concat(["custom"]);}}]} : null}));
            Notify.popups=[];
        }
        function focus(name:string):bool {
            if(name==="list"){flick.forceActiveFocus();return true;}
            if(name==="custom") {const c=notificationCards.itemAt(0);const a=root.testFind(c,"A very long custom action label ".repeat(8));if(a){a.forceActiveFocus();return true;}return false;}
            const item=root.testFind(keys,name);if(!item)return false;item.forceActiveFocus();return true;
        }
        function query(value:string):void {root.query=value;}
        function select(key:string):void {root.selectedKey=key;}
        function prepend():void {Notify.history=[{key:"new",appName:"Fixture app",summary:"Incoming",body:"New notification",time:new Date(),urgency:1}].concat(Notify.history);}
        function empty():void {Notify.clear();}
    }
''' + s[end:]; p.write_text(s)


def exercise(run, launch, wait, ipc, processes, shell, args):
    results = []
    def state(): return json.loads(ipc('centerProbe','state'))
    def record(name, ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/center-results.json').write_text(json.dumps(results,indent=2))
        assert ok,(name,state())
    def pointer(*cmd): run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','90000'],'center-seat.log')
    def key(code,mod=None): pointer('pause',80,*(['mod',mod] if mod else []),'tap',code,*(['mod','none'] if mod else []),'pause',150)
    def focus(name): assert ipc('centerProbe','focus',name)=='true',name;time.sleep(.15)
    def click(name,button=272):
        focus(name);p=state()['rect'];pointer('move',round((p['x']+p['w']/2)*args.scale),round((p['y']+p['h']/2)*args.scale),'click',button,'pause',150)
    def shot(name): time.sleep(.2);run(['grim','/work/center-'+name+'.png'])
    def opened(): return any(l['namespace']=='nbshell:notification-center' and l['mapped'] for l in json.loads(run(['/test-bin/umbriel','layers','--json']).stdout))
    target=Path('/work/center-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Notification Center focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'center-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focused')
    ipc('notify','center');wait(opened,'center open');time.sleep(.3)
    ipc('centerProbe','setup');time.sleep(.3)
    record('native search initially focused',state()['focus']=='Search notifications')
    s=state();b=s['box'];f=s['footer']
    record('panel and footer fit output',b['x']>=0 and b['y']>=0 and b['x']+b['w']<=args.width/args.scale and b['y']+b['h']<=args.height/args.scale and f['y']+f['h']<=b['y']+b['h'])
    record('all history entries reachable',s['rows']==30)
    shot('initial')
    key(32);key(45);key(57);key(46)
    record('d x space c are search text, not destructive shortcuts',state()['query']=='dx c' and state()['count']==30 and not state()['dnd'])
    shot('no-matches');key(1)
    record('Escape clears search without closing',opened() and state()['query']=='')
    key(108);record('Down enters selected history row',state()['focus']=='Notification history' and state()['key']=='fixture-0')
    key(107);record('End reaches final row and scrolls',state()['key']=='fixture-29' and state()['scroll']>0)
    shot('last-row');key(15)
    record('Tab from list reaches selected notification action',state()['focus']=='Open' and state()['key']=='fixture-29')
    key(15)
    record('Tab reaches selected dismiss with visible focus',state()['focus']=='Dismiss' and state()['rect']['y']>=state()['list']['y'] and state()['rect']['y']+state()['rect']['h']<=state()['list']['y']+state()['list']['h'])
    focus('list');key(111)
    record('Delete only dismisses selected row',state()['count']==29 and state()['actions']==[])
    ipc('centerProbe','select','fixture-20');ipc('centerProbe','prepend');time.sleep(.3)
    record('new arrival preserves stable selection',state()['key']=='fixture-20')
    key(111);record('dismiss after prepend targets same row',state()['count']==29 and state()['actions']==[])
    focus('Search notifications');key(30,'ctrl');key(45)
    record('native Ctrl+A and typing remain usable',state()['query']=='x')
    key(1);focus('list');key(32)
    record('list D toggles native DND',state()['dnd'])
    key(46,'ctrl');record('first clear arms without clearing',state()['armed'] and state()['count']==29)
    key(1);record('Escape cancels clear before closing',not state()['armed'] and opened() and state()['count']==29)
    focus('Clear all');key(28);time.sleep(3.2)
    record('clear confirmation expires',not state()['armed'] and state()['count']==29)
    ipc('centerProbe','query','Notification 12');time.sleep(.2)
    record('search finds older stored notification',state()['rows']==1 and state()['key']=='fixture-12')
    focus('list');key(28);wait(lambda:not opened(),'open closes center')
    key(30);record('Escape or activation returns application focus',underlying()['keys']==[65])
    ipc('notify','center');wait(opened,'reopen');time.sleep(.3)
    record('archived notification Open focuses exact app entry',state()['actions']==['focus:fixture-12'])
    ipc('centerProbe','setup');time.sleep(.2)
    focus('custom');shot('long-action')
    record('long custom action fits and focused control is visible',state()['rect']['x']+state()['rect']['w']<=state()['list']['x']+state()['list']['w'] and state()['rect']['y']>=state()['list']['y'] and state()['rect']['y']+state()['rect']['h']<=state()['list']['y']+state()['list']['h'])
    key(28)
    record('custom live action dispatched exactly once',state()['actions']==['custom'] and opened())
    ipc('centerProbe','select','fixture-0');focus('list');key(28);wait(lambda:not opened(),'default closes center')
    ipc('notify','center');wait(opened,'reopen after default');time.sleep(.3)
    record('Open preserves default notification action',state()['actions']==['custom','default'])
    ipc('centerProbe','query','Notification 10');time.sleep(.2)
    click('Dismiss');record('pointer dismiss does not open notification',opened() and state()['rows']==0 and state()['actions']==['custom','default'])
    key(1);click('DND on');record('pointer DND restores off',not state()['dnd'])
    click('Clear all');record('pointer clear requires confirmation',state()['armed'] and state()['count']>0);shot('confirm')
    click('Confirm clear');record('confirmed clear empties history',state()['count']==0 and not state()['clearEnabled'] and state()['key']=='')
    shot('empty')
    key(1);wait(lambda:not opened(),'Escape closes empty center');key(48)
    record('final Escape restores underlying focus',underlying()['keys']==[65,66])
    ipc('notify','center');wait(opened,'open for outside dismissal');time.sleep(.3)
    pointer('move',2,2,'click',272,'pause',300);wait(lambda:not opened(),'outside click closes')
    record('outside click dismisses overlay',True)
    log=Path('/work/shell.log').read_text()
    record('no QML binding or type errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
