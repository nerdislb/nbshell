"""Private native shortcut-help checks; bindings are inert reference data."""
import json
import re
import subprocess
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Services/Binds.qml';s=p.read_text().replace('    id: root','    id: root\n    property int testLoads: 0\n    property bool testMounted: false',1)
    s=re.sub(r'    function load\(\) \{.*?\n    }', '''    function load() {
        if (loading) return;
        testLoads++;
        loading=true;
    }''',s,flags=re.S);p.write_text(s)
    p=shell/'Keys/KeysWindow.qml';s=p.read_text().replace('    id: root','''    id: root
    QtObject { Component.onCompleted: Binds.testMounted=true }
    Component.onDestruction: Binds.testMounted=false''',1);end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    function testRect(item) {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
    IpcHandler {
        target:"keysProbe"
        function state():string {
            const item=list.currentItem,f=search.Window.window.activeFocusItem;
            return JSON.stringify({query:root.query,key:root.selectedKey,index:root.selected,
                count:root.matches.length,groups:root.rows.filter(r=>r.header).map(r=>r.text),
                focus:f?.accessibleName||"",searchFocused:search.activeFocus,
                refreshEnabled:refreshButton.enabled,refresh:root.testRect(refreshButton),
                row:item?root.testRect(item):{},list:root.testRect(list),box:root.testRect(box),footer:root.testRect(footer),
                cursor:search.cursorPosition,selectedText:search.selectedText,scroll:list.contentY,compact:root.compact,
                status:status.text,loading:Binds.loading,
                rowVisible:!!item && item.y>=list.contentY-1 && item.y+item.height<=list.contentY+list.height+1});
        }
        function query(value:string):void {search.text=value;root.focusSearch(false);}
        function accessibleRefresh():void {refreshButton.Accessible.pressAction();}
        function accessibleRow():void {list.currentItem.Accessible.pressAction();}
        function rowRect(index:int):string {const item=rowsRepeater.itemAt(index);return JSON.stringify(item?root.testRect(item):{});}
    }
'''+s[end:];p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"keysFixture"
        function setup():void {
            Binds.list=Array.from({length:63},(_,i)=>({taste:"Mod+"+String(i).padStart(2,"0"),
                text:i===0?"Open terminal":i===62?"Last custom shortcut":i===9?"A long literal <b>description</b> "+"with wrapped words ".repeat(6):"Fixture shortcut "+i,
                aktion:"spawn:touch /work/unexpected-shortcut-dispatch",gruppe:i%9===8?"Custom":Binds.gruppen[i%9]}));
            Binds.problem="";Binds.loading=false;
        }
        function state():string {return JSON.stringify({open:Runtime.keysOpen,mounted:Binds.testMounted,loads:Binds.testLoads});}
        function finish():void {Binds.loading=false;Binds.problem="";}
        function error():void {Binds.loading=false;Binds.problem="Fixture read failure <b>literal</b>";}
        function empty():void {Binds.list=[];Binds.problem="";Binds.loading=false;}
        function prepend():void {Binds.list=[{taste:"Mod+New",text:"New concurrent binding",aktion:"none",gruppe:"Applications"}].concat(Binds.list);}
        function remove():void {Binds.list=Binds.list.filter(b=>b.taste!=="Mod+62");}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('keysProbe','state'))
    def service():return json.loads(ipc('keysFixture','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/keys-results.json').write_text(json.dumps(results,indent=2))
        if not ok:print('FAILED STATE',state() if service()['mounted'] else service(),flush=True)
        assert ok,name
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','120000'],'keys-seat.log')
    def key(code,mod=None):pointer('pause',50,*(['mod',mod] if mod else []),'tap',code,*(['mod','none'] if mod else []),'pause',100)
    def shot(name):time.sleep(.15);run(['grim','/work/keys-'+name+'.png'])
    def query(value):ipc('keysProbe','query',value);time.sleep(.12)
    def open_menu():ipc('keys','open');wait(lambda:service()['mounted'],'keys mapped');time.sleep(.15)
    def closed():return not service()['mounted'] and not service()['open']
    target=Path('/work/keys-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Keys focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'keys-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus');ipc('keysFixture','setup');open_menu()
    s=state();b=s['box'];f=s['footer']
    record('all bindings and known plus custom groups retained',s['count']==63 and len(s['groups'])==9 and s['groups'][-1]=='Custom')
    record('native search initially focused',s['searchFocused'])
    record('card footer and list fit output',b['x']>=0 and b['y']>=0 and b['x']+b['w']<=args.width/args.scale and b['y']+b['h']<=args.height/args.scale and f['y']+f['h']<=b['y']+b['h'] and s['list']['h']>0)
    record('compact layout follows available character width',s['compact']==(args.width<600));shot('initial')
    key(15);record('Tab reaches visible Refresh',state()['focus']=='Refresh keyboard shortcuts')
    key(15);record('Tab enters first data row not group header',state()['focus']=='Mod+00: Open terminal')
    key(108);record('Down navigates next binding within group',state()['focus'].startswith('Mod+09:'))
    record('long literal content remains fully visible',state()['rowVisible']);shot('long')
    key(107);last=state()['key'];record('End reaches last custom binding and scrolls',state()['focus']=='Mod+62: Last custom shortcut' and state()['rowVisible'] and state()['scroll']>0);shot('last')
    ipc('keysFixture','prepend');time.sleep(.2)
    record('refresh insertion preserves selected identity and focus',state()['key']==last and state()['focus']=='Mod+62: Last custom shortcut')
    ipc('keysFixture','remove');time.sleep(.2)
    record('removed selection reconciles to a valid focused row',state()['key']!=last and state()['index']>=0 and state()['rowVisible'])
    key(102);key(109);record('PageDown advances without executing',state()['index']>1 and state()['rowVisible'])
    key(104);record('PageUp returns to first binding',state()['index']==1)
    key(28);key(57);ipc('keysProbe','accessibleRow')
    record('Enter Space and accessibility remain reference only',service()['open'] and not Path('/work/unexpected-shortcut-dispatch').exists())
    key(15);record('Tab returns from row to search',state()['searchFocused'])
    for code in [20,18,19,50]:key(code)
    record('native typing filters descriptions',state()['query']=='term' and state()['count']==1)
    key(105);record('Left edits caret without browsing',state()['cursor']==3)
    key(30,'ctrl');record('Ctrl+A selects native query',state()['selectedText']=='term')
    subprocess.run(['wl-copy','--','Workspaces'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=5);key(47,'ctrl')
    record('native paste and group search work',state()['query']=='Workspaces' and state()['count']==7)
    query('Mod+01');record('key search preserved',state()['count']==1)
    query('unexpected-shortcut-dispatch');record('underlying action search preserved',state()['count']==62)
    query('no <b>matches</b>');record('no-match state clears selected row',state()['count']==0 and state()['index']==-1);shot('no-match')
    key(28);record('Enter with no results is harmless',service()['open'] and state()['searchFocused'])
    key(1);record('Escape clears filter before closing',state()['query']=='' and service()['open'])
    key(63);record('F5 starts one refresh and disables button',service()['loads']==1 and state()['loading'] and not state()['refreshEnabled']);shot('loading')
    key(63);ipc('keysProbe','accessibleRefresh');record('loading suppresses redundant refresh',service()['loads']==1)
    ipc('keysFixture','error');time.sleep(.12)
    record('refresh error retains cached rows and recovers control',state()['count']==63 and state()['refreshEnabled'] and 'Fixture read failure' in state()['status']);shot('error')
    p=state()['refresh'];pointer('move',round((p['x']+p['w']/2)*args.scale),round((p['y']+p['h']/2)*args.scale),'click',272,'pause',100)
    record('pointer refresh retries and does not leave disabled focus',service()['loads']==2 and state()['searchFocused'])
    ipc('keysFixture','finish');ipc('keysProbe','accessibleRefresh');record('accessible refresh uses same load guard',service()['loads']==3)
    ipc('keysFixture','finish');key(108);key(63);ipc('keysFixture','prepend');ipc('keysFixture','finish');time.sleep(.15)
    record('refresh while browsing keeps row focus',not state()['searchFocused'] and state()['rowVisible'])
    key(33,'ctrl');record('Ctrl+F focuses native search',state()['searchFocused'])
    ipc('keysFixture','empty');time.sleep(.15);record('empty configuration is distinct from loading',state()['count']==0 and state()['status']=='' and state()['searchFocused']);shot('empty')
    key(63);record('empty-list refresh exposes loading state',state()['loading']);ipc('keysFixture','error');time.sleep(.1);shot('unavailable')
    record('empty-list error remains retryable',state()['count']==0 and state()['refreshEnabled'] and bool(state()['status']))
    key(1);wait(closed,'Escape closes');key(30)
    record('Escape restores application keyboard focus',underlying()['focused'] and underlying()['keys']==[65])
    ipc('keysFixture','setup');open_menu();record('reopen resets query and focus',state()['query']=='' and state()['searchFocused'])
    pointer('move',2,2,'click',272,'pause',100);wait(closed,'outside closes')
    record('outside click closes without executing bindings',not Path('/work/unexpected-shortcut-dispatch').exists())
    open_menu();query('term');ipc('keys','toggle');wait(closed,'IPC closes');open_menu();record('IPC reopen resets query',state()['query']=='');key(1);wait(closed,'final close')
    log=Path('/work/shell.log').read_text()
    record('no QML type or binding errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
