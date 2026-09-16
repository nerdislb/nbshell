"""Bar arrangement contract; all mutations target a private fixture config."""
import json
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Settings/ModulesMenu.qml';s=p.read_text().replace('readonly property var catalog: Plugins.ids','property var catalog: Plugins.ids')
    end=s.rfind('}');s='import Quickshell.Io\n'+s[:end]+'''
    IpcHandler {
        target:"modulesProbe"
        function rect(item:var):var {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
        function state():string {
            const f=keys.Window.window.activeFocusItem;
            return JSON.stringify({open:Runtime.modulesOpen,focused:keys.activeFocus,name:f?.accessibleName||f?.Accessible.name||"",
                focus:f ? rect(f) : {},group:root.groupIndex,item:root.itemIndex,inCatalog:root.inCatalog,footer:root.footerFocused,
                catalogIndex:root.catalogIndex,catalog:root.catalog,lists:root.groups.map((g,i)=>root.listOf(i)),
                saving:Config.saving,error:Config.writeError,readError:Config.readError,
                left:rect(leftScroll),right:rect(rightScroll),leftY:leftScroll.contentY,rightY:rightScroll.contentY,
                head:rect(head),bottom:rect(footer),height:root.height,drag:root.dragGroup});
        }
        function setup():void {
            Config.setValues({mode:"bar",collapsedWidgets:["clock"],leftWidgets:["clock","workspaces"],centerWidgets:[],rightWidgets:["battery"]});
            root.catalog=Plugins.ids.concat(Array.from({length:20},(_,i)=>"fixture-long-module-"+i));
        }
        function choose(group:int,item:int,catalog:int):void {
            root.footerFocused=false;root.groupIndex=group;root.itemIndex=item;
            root.inCatalog=catalog>=0;if(catalog>=0)root.catalogIndex=catalog;
            Qt.callLater(root.syncFocus);
        }
        function at(group:int,index:int):string {return JSON.stringify(rect(groupRows.itemAt(group).rowAt(index)));}
        function header(group:int):string {return JSON.stringify(rect(groupRows.itemAt(group).children[0]));}
        function valid(value:bool):void {Config.configValid=value;Config.readError=value ? "" : "Fixture configuration is read-only";}
        function islandOnly():void {Config.setValues({collapsedWidgets:["clock"],leftWidgets:["workspaces"],centerWidgets:[],rightWidgets:[]});}
        function clear():void {Config.setValues({collapsedWidgets:[],leftWidgets:[],centerWidgets:[],rightWidgets:[]});}
        function emptyCatalog():void {root.catalog=[];root.catalogIndex=0;}
        function close():void {root.close();}
    }
''' +s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('modulesProbe','state'))
    def runtime():return json.loads(ipc('state','dump'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/modules-results.json').write_text(json.dumps(results,indent=2));assert ok,(name,state() if runtime()['modules'] else runtime())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','90000'],'modules-seat.log')
    def key(code,shift=False):pointer('pause',180,*(['mod','shift'] if shift else []),'tap',code,'pause',160)
    def shot(name):time.sleep(.15);run(['grim','/work/modules-'+name+'.png'])
    target=Path('/work/modules-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot { property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Modules focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'modules-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying window')
    ipc('settings','modules');wait(lambda:state()['focused'],'modules focus')
    ipc('modulesProbe','setup');wait(lambda:not state()['saving'],'fixture persisted')
    ipc('modulesProbe','choose','1','0','-1');time.sleep(.2);shot('initial')
    record('starts in visible bar group',state()['group']==1 and state()['name']=='Clock')
    record('heading and footer fit output',state()['head']['y']>=0 and state()['bottom']['y']+state()['bottom']['h']<=state()['height'])
    before=state()['lists'];key(108);wait(lambda:state()['item']==1,'Down selects')
    record('selection does not edit layout',state()['lists']==before)
    key(105);wait(lambda:state()['lists'][1]==['workspaces','clock'],'Left reorders')
    record('reorder preserves items',state()['item']==0)
    key(106,True);wait(lambda:state()['lists'][2]==['workspaces'],'Shift Right changes group')
    wait(lambda:not state()['saving'],'move persisted')
    disk=json.loads(Path('/home/user/.config/nbshell/config.json').read_text())
    record('cross-group move is persisted atomically',disk['leftWidgets']==['clock'] and disk['centerWidgets']==['workspaces'])
    key(111);wait(lambda:state()['lists'][2]==[],'Delete removes')
    record('empty group stays focused',state()['name']=='No modules' and state()['group']==2)
    key(28);wait(lambda:state()['inCatalog'],'empty group Enter')
    record('empty group opens available list',state()['focused'])
    sep=state()['catalog'].index('sep');ipc('modulesProbe','choose','2','0',str(sep));time.sleep(.2);key(28)
    wait(lambda:state()['lists'][2]==['sep'],'add separator')
    key(28);wait(lambda:state()['lists'][2]==['sep','sep'],'add second separator')
    record('repeatable separators retained',state()['lists'][2]==['sep','sep'])
    clock=state()['catalog'].index('clock');ipc('modulesProbe','choose','2','0',str(clock));time.sleep(.2);key(28)
    wait(lambda:not state()['inCatalog'],'existing module selects placement')
    record('existing module does not duplicate',state()['group']==1 and state()['lists'][1]==['clock'])
    key(15);wait(lambda:state()['inCatalog'],'Tab catalogue')
    key(15);wait(lambda:state()['footer'],'Tab close')
    record('Close reachable through Tab',state()['name']=='Close')
    key(15,True);wait(lambda:state()['inCatalog'] and not state()['footer'],'ShiftTab catalogue')
    record('reverse tab restores catalogue',state()['focused'])
    ipc('modulesProbe','choose','1','0',str(len(state()['catalog'])-1));time.sleep(.2)
    v=state();record('long catalogue scrolls and focused row is visible',v['rightY']>0 and v['focus']['y']>=v['right']['y'] and v['focus']['y']+v['focus']['h']<=v['right']['y']+v['right']['h']+1);shot('catalogue-end')
    # Real pointer drag, with several intermediate motions beyond the drag threshold.
    ipc('modulesProbe','setup');wait(lambda:not state()['saving'],'reset fixture')
    ipc('modulesProbe','choose','1','0','-1');time.sleep(.2)
    a=json.loads(ipc('modulesProbe','at','1','0'));b=json.loads(ipc('modulesProbe','at','1','1'))
    x=a['x']+a['w']*.45;y=a['y']+a['h']/2;targetY=b['y']+b['h']*.8
    pointer('move',x,y,'pause',100,'press',272,'pause',100,'move',x+12,y+8,'pause',100,'move',x+14,(y+targetY)/2,'pause',100,'move',x,targetY,'pause',150,'release',272,'pause',200)
    wait(lambda:state()['lists'][1]==['workspaces','clock'],'pointer drag reorder')
    record('native drag reorders without losing modules',state()['drag']==-1);shot('dragged')
    # Drop onto the next group's header (also supports empty groups).
    ipc('modulesProbe','choose','1','0','-1');time.sleep(.2)
    a=json.loads(ipc('modulesProbe','at','1','0'));b=json.loads(ipc('modulesProbe','header','2'))
    x=a['x']+a['w']*.45;y=a['y']+a['h']/2;targetY=b['y']+b['h']/2
    pointer('move',x,y,'pause',100,'press',272,'pause',100,'move',x+12,y+8,'pause',100,'move',x+14,(y+targetY)/2,'pause',100,'move',x,targetY,'pause',150,'release',272,'pause',200)
    wait(lambda:state()['lists'][2]==['workspaces'],'drag to empty group')
    record('native drag moves into empty group',state()['lists'][1]==['clock'] and state()['drag']==-1)
    ipc('modulesProbe','choose','1','0','-1');time.sleep(.2)
    before=state()['lists'];a=json.loads(ipc('modulesProbe','at','1','0'));x=a['x']+a['w']*.45;y=a['y']+a['h']/2
    pointer('move',x,y,'pause',100,'press',272,'pause',100,'move',x+12,y+8,'pause',100,'move',3,3,'pause',150,'release',272,'pause',200)
    record('cancelled drag leaves layout intact',state()['lists']==before and state()['drag']==-1)
    ipc('modulesProbe','islandOnly');wait(lambda:not state()['saving'],'island-only fixture')
    ipc('modulesProbe','choose','1','0',str(state()['catalog'].index('clock')));time.sleep(.2);key(28)
    wait(lambda:state()['lists'][1]==['workspaces','clock'],'add island module to visible bar')
    record('collapsed-island list stays independent from bar placement',state()['lists'][0]==['clock'])
    ipc('modulesProbe','valid','false');ipc('modulesProbe','choose','1','0','-1');time.sleep(.2)
    before=state()['lists'];key(111);key(106,True)
    record('read-only configuration blocks layout edits',state()['lists']==before);shot('read-only')
    ipc('modulesProbe','valid','true');ipc('modulesProbe','clear');wait(lambda:all(not x for x in state()['lists']),'clear private fixture')
    ipc('modulesProbe','choose','1','0','-1');time.sleep(.2)
    record('all-empty layout remains navigable',state()['name']=='No modules')
    ipc('modulesProbe','emptyCatalog');shot('empty')
    key(15);wait(lambda:state()['footer'],'empty catalogue tab skips to close')
    record('empty catalogue has working close navigation',state()['name']=='Close')
    key(1);wait(lambda:not runtime()['modules'],'Escape closes')
    wait(lambda:underlying()['focused'],'focus restored')
    record('Escape restores focus without forwarding key',not underlying()['keys'])
    ipc('settings','modules');wait(lambda:state()['focused'],'reopen empty')
    record('reopening resets footer focus',not state()['footer'])
    pointer('move',2,args.height-2,'pause',100,'click',272,'pause',150)
    wait(lambda:not runtime()['modules'],'outside close');record('outside click dismisses',not runtime()['modules'])
    log=Path('/work/shell.log').read_text();record('no QML type/reference/binding errors',not any(x in log for x in ['TypeError','ReferenceError','Binding loop']))
    print(json.dumps({'modulesChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
