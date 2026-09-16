"""Native settings navigation in a private home/Wayland session."""
import json
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Settings/SettingsMenu.qml';s=p.read_text();end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    IpcHandler {
        target: root.embedded ? "embeddedSettingsProbe" : "settingsProbe"
        enabled: root.visible
        function state():string {
            const f=keys.Window.window.activeFocusItem;
            const pos=f ? f.mapToItem(root,0,0) : Qt.point(0,0);
            return JSON.stringify({pane:root.pane,group:root.group,selected:root.selected,
                name:f?.accessibleName||f?.Accessible.name||"",focused:keys.activeFocus,
                x:pos.x,y:pos.y,w:f?.width||0,h:f?.height||0,
                head:heading.mapToItem(root,0,0).y,
                footer:footer.mapToItem(root,0,0).y+footer.height,
                bodyTop:body.mapToItem(root,0,0).y,bodyBottom:body.mapToItem(root,0,0).y+body.height,
                width:root.width,height:root.height,scroll:viewport.contentY,
                groups:root.groups.length,items:root.items.length,
                gap:Config.value("gap",6),accent:Config.value("accent","theme"),saving:Config.saving,
                readError:Config.readError,writeError:Config.writeError});
        }
        function choose(group:int,row:int,pane:int):void {root.group=group;root.selected=row;root.pane=pane;Qt.callLater(root.syncFocus);}
        function valid(value:bool):void {Config.configValid=value;Config.readError=value ? "" : "Fixture invalid configuration";}
        function step():void {root.step(root.items[root.selected],1);}
        function close():void {root.close();}
    }
''' +s[end:];p.write_text(s)

    p=shell/'Menu/Menu.qml';s=p.read_text();end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    IpcHandler {
        target: "settingsMenuProbe"
        function enter():void {root.openSettings();}
        function state():string {return JSON.stringify({open:Runtime.menuOpen,settings:root.settingsPage,plugins:Runtime.pluginDeveloperOpen});}
        function close():void {root.close();Runtime.pluginDeveloperOpen=false;}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('settingsProbe','state'))
    def runtime():return json.loads(ipc('state','dump'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/settings-results.json').write_text(json.dumps(results,indent=2));assert ok,(name,state() if runtime()['settings'] else runtime())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    # Keep one keyboard present across separate native pointer/key commands.
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','90000'],'settings-seat.log')
    def key(code,shift=False):
        pointer('pause',180,*(['mod','shift'] if shift else []),'tap',code,'pause',120)
    def shot(name):time.sleep(.15);run(['grim','/work/settings-'+name+'.png'])
    def open_panel():ipc('settings','open');wait(lambda:state()['focused'],'settings focus')
    target=Path('/work/settings-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot { property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Settings focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'settings-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying window')
    open_panel();shot('initial')
    record('starts in categories without editing',state()['pane']==0 and state()['name']=='Bar')
    record('fixed heading and footer fit',state()['head']>=0 and state()['footer']<=state()['height'])
    key(108);wait(lambda:state()['group']==1,'Down category')
    record('category navigation keeps settings unchanged',state()['accent']=='theme' and state()['gap']==6)
    key(108);wait(lambda:state()['group']==2,'Appearance category')
    key(28);wait(lambda:state()['pane']==1,'Enter category')
    record('category Enter enters options without changing them',state()['accent']=='theme' and state()['name']=='Accent color')
    key(106);wait(lambda:state()['accent']=='red' and not state()['saving'],'Right changes option')
    record('Right persists through real private writer',json.loads(Path('/home/user/.config/nbshell/config.json').read_text())['accent']=='red')
    key(105);wait(lambda:state()['accent']=='theme','Left restores option')
    record('Left changes back',state()['pane']==1)
    key(15);wait(lambda:state()['pane']==3,'Tab close')
    record('Close reachable through Tab',state()['name']=='Close')
    key(15,True);wait(lambda:state()['pane']==1,'ShiftTab options')
    record('reverse tab returns to options',state()['name']=='Accent color')
    ipc('settingsProbe','choose','6','12','1');wait(lambda:state()['selected']==12 and state()['scroll']>0,'last Services option')
    record('long options scroll independently',state()['scroll']>0)
    record('last focused option is fully inside body',state()['y']>=state()['bodyTop'] and state()['y']+state()['h']<=state()['bodyBottom']+1)
    record('header and Close remain visible after scrolling',state()['head']>=0 and state()['footer']<=state()['height']);shot('scrolled')
    key(1);wait(lambda:not runtime()['settings'],'Escape closes')
    wait(lambda:underlying()['focused'],'underlying focus restored')
    record('Escape restores focus without forwarding key',not underlying()['keys'])
    open_panel();record('reopening resets category and scroll',state()['group']==0 and state()['pane']==0 and state()['scroll']==0)
    ipc('settingsProbe','choose','0','2','1');time.sleep(.15);v=state()
    pointer('move',v['x']+v['w']/2,v['y']+v['h']/2,'pause',100,'click',272,'pause',120)
    wait(lambda:state()['gap']==7,'pointer option click')
    record('pointer uses same value change path',state()['gap']==7)
    pointer('click',273,'pause',120);wait(lambda:state()['gap']==6,'right click decrement')
    record('right-click backward retained',state()['gap']==6)
    ipc('settingsProbe','valid','false');ipc('settingsProbe','choose','0','2','1')
    key(106);record('invalid configuration blocks edits',state()['gap']==6)
    key(15);wait(lambda:state()['pane']==2,'Tab recovery')
    record('recovery remains keyboard reachable',state()['name']=='Open configuration recovery');shot('recovery')
    ipc('settingsProbe','valid','true');wait(lambda:state()['pane']==0,'repair restores navigation')
    record('repair clears recovery focus state',state()['focused'])
    ipc('settingsProbe','valid','false');ipc('settingsProbe','choose','0','2','2')
    key(15);wait(lambda:state()['pane']==3,'recovery to close');key(28)
    wait(lambda:not runtime()['settings'],'Close activates')
    record('Close button works with invalid config',not runtime()['settings'])
    open_panel();ipc('settingsProbe','valid','true')
    ipc('settingsProbe','choose','1','0','1');time.sleep(.15);key(28)
    wait(lambda:runtime()['modules'] and not runtime()['settings'],'module handoff')
    record('Arrange action hands off after settings closes',runtime()['modules'] and not runtime()['settings'])
    ipc('lifecycleProbe','closePanels');wait(lambda:not runtime()['modules'],'module close')
    open_panel();pointer('move',2,2,'pause',100,'click',272,'pause',120)
    wait(lambda:not runtime()['settings'],'outside close');record('outside click dismisses',not runtime()['settings'])
    ipc('menu','open');ipc('settingsMenuProbe','enter')
    def embedded():return json.loads(ipc('embeddedSettingsProbe','state'))
    def menu():return json.loads(ipc('settingsMenuProbe','state'))
    wait(lambda:embedded()['focused'],'embedded settings focus')
    record('embedded menu settings shares accessible navigation',embedded()['pane']==0 and embedded()['name']=='Bar')
    key(1);wait(lambda:not menu()['settings'],'Escape returns to main menu')
    record('embedded Escape returns without closing menu',menu()['open'])
    ipc('settingsMenuProbe','enter');wait(lambda:embedded()['focused'],'embedded re-entry')
    ipc('embeddedSettingsProbe','choose','1','1','1');time.sleep(.15);key(28)
    wait(lambda:menu()['plugins'] and not menu()['open'],'plugin manager handoff')
    record('embedded plugin action closes menu and opens manager',menu()['plugins'] and not menu()['open'])
    ipc('settingsMenuProbe','close')
    log=Path('/work/shell.log').read_text()
    record('no QML type/reference/binding errors',not any(x in log for x in ['TypeError','ReferenceError','Binding loop']))
    print(json.dumps({'settingsChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
