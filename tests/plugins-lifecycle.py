"""Plugin manager UI checks; fixtures never install or execute third-party code."""
import json
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Services/Plugins.qml';s=p.read_text().replace('function refresh()', 'function unusedRefresh()')
    s=s.replace('id: root','id: root\n    function refresh() {}',1);p.write_text(s)
    p=shell/'Settings/PluginDeveloper.qml';s=p.read_text()
    s=s.replace('actionProc.command = command;\n        actionProc.running = true;', 'testActions = testActions.concat([action]); busy = false;')
    s=s.replace('["bash", Plugins.script, "diff", targetName(item)]','["printf", "Fixture update diff\\n"]')
    end=s.rfind('}');s=s[:end]+'''
    property var testActions: []
    IpcHandler {
        target: "pluginsProbe"
        function rect(item:var):var {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
        function state():string {
            const f=keys.Window.window.activeFocusItem;
            return JSON.stringify({open:Runtime.pluginDeveloperOpen,tab:root.tab,query:root.query,count:root.list.length,
                selected:root.selected,pending:root.pendingAction,actions:root.testActions,busy:root.busy,
                name:f?.accessibleName||f?.Accessible.name||"",focus:f ? rect(f) : {},
                search:search.activeFocus,footer:rect(footerRow),body:rect(browser),detail:rect(detailScroll),
                detailY:detailScroll.contentY,listY:pluginScroll.contentY,height:root.height,
                row:pluginRepeater.itemAt(root.selected) ? rect(pluginRepeater.itemAt(root.selected)) : {},
                removeVisible:removeButton.visible,modalButtons:rect(confirmationButtons),modal:rect(confirmationModal.panel),modalY:confirmationScroll.contentY,enabled:Plugins.enabledIds});
        }
        function setup():void {
            Plugins.plugins=Array.from({length:35},(_,i)=>({id:"fixture.plugin."+i,name:"Plugin "+i,
                author:"Fixture author",description:("Long plugin description. ").repeat(i===34?24:2),
                license:"MIT",repository:"https://example.invalid/plugin",managed:false,gitManaged:true,kinds:[],
                dependencies:{commands:["fixture-command", "second-command"]}}));
            root.catalog=[{id:"fixture.store",name:"Store fixture",repository:"https://example.invalid/store",description:"Not installed",kinds:[]}];
        }
        function query(value:string):void {root.query=value;}
        function choose(index:int):void {root.selected=index;search.forceActiveFocus();}
        function tab(value:string):void {root.selectTab(value);}
        function remove():void {root.ask("remove",root.plugin,"Remove the fixture plugin?",root.activeFocusItem);}
        function confirm():void {root.confirmPending();}
        function preview():void {root.previewUpdate(root.plugin);}
        function busy(value:bool):void {root.busy=value;}
        function activate():void {root.primaryAction(root.plugin);}
        function empty():void {Plugins.plugins=[];root.catalog=[];}
        function error():void {root.catalogError="Fixture catalog error";root.statusText="Fixture operation failed";root.statusError=true;}
        function longDiff():void {root.ask("update",root.plugin,("+ Long fixture diff line\\n").repeat(80));}
        function badRepository():void {root.catalog=[{id:"bad",name:"Bad repository",repository:""}];}
        function close():void {root.close();}
    }
''' + s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('pluginsProbe','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/plugins-results.json').write_text(json.dumps(results,indent=2));assert ok,(name,state())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','90000'],'plugins-seat.log')
    def key(code,mod=None):pointer('pause',150,*(['mod',mod] if mod else []),'tap',code,'pause',140)
    def shot(name):time.sleep(.2);run(['grim','/work/plugins-'+name+'.png'])
    target=Path('/work/plugins-focus-target');target.mkdir()
    (target/'shell.qml').write_text("""import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot { property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Plugins focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}""")
    launch(['/test-bin/qs','-p',str(target)],'plugins-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    def mapped():return any(x['namespace']=='nbshell:plugin-manager' and x['mapped'] for x in json.loads(run(['/test-bin/umbriel','layers','--json']).stdout))
    wait(lambda:underlying()['focused'],'underlying window')
    ipc('plugins','developer');wait(lambda:state()['search'],'plugin search focus')
    ipc('pluginsProbe','setup');wait(lambda:state()['count']==35,'fixture ready');shot('initial')
    record('initial search and all plugins available',state()['search'] and state()['count']==35)
    key(108);record('Down selects without enabling',state()['selected']==1 and not state()['enabled'])
    key(15);key(108)
    record('row keyboard focus follows selection',state()['selected']==2 and state()['name']=='Plugin 2')
    # A native pointer selects without enabling or installing.
    v=state();pointer('move',v['row']['x']+30,v['row']['y']+15,'pause',100,'click',272,'pause',100)
    record('row click never executes a plugin action',not state()['enabled'] and not state()['actions'])
    ipc('pluginsProbe','choose','34');time.sleep(.2)
    v=state();record('last item visible after keyboard selection',v['listY']>0 and v['row']['y']>=v['body']['y'] and v['row']['y']+v['row']['h']<=v['body']['y']+v['body']['h']+1)
    # Tab visits one selected list row, then detail actions; focus reveals them.
    key(15);key(15);v=state()
    record('detail action is reached and scrolled into view',v['name']=='ENABLE' and v['focus']['y']>=v['detail']['y'] and v['focus']['y']+v['focus']['h']<=v['detail']['y']+v['detail']['h']+1)
    shot('details')
    key(15);key(15);key(15);record('Remove reachable by keyboard',state()['name']=='REMOVE')
    key(28);wait(lambda:state()['pending']=='remove','remove dialog')
    record('remove waits for confirmation',not state()['actions'] and state()['name']=='CANCEL');shot('confirm')
    key(1);wait(lambda:state()['pending']=='','cancel')
    record('Escape cancels and restores action focus',state()['name']=='REMOVE' and not state()['actions'])
    key(15);record('Close reachable after detail actions',state()['name']=='Close')
    v=state();record('footer inside output',v['footer']['y']+v['footer']['h']<=v['height'])
    ipc('pluginsProbe','choose','0');key(3) # literal 2 in search, not tab switch
    record('numeric search does not switch tabs',state()['tab']=='installed' and state()['query']=='2')
    key(1);record('Escape clears query before closing',state()['query']=='')
    ipc('pluginsProbe','query','missing-fixture');wait(lambda:state()['count']==0,'empty search');shot('empty')
    key(108);record('empty list keeps nonnegative cursor',state()['selected']==0)
    key(1);wait(lambda:state()['count']==35,'clear query')
    key(3,'alt');wait(lambda:state()['tab']=='store','Alt2 store')
    record('Store retains search focus',state()['search'])
    record('uninstalled Store entry has no Remove action',not state()['removeVisible'])
    key(28);wait(lambda:state()['pending']=='install','install confirmation')
    record('install is not implicit',not state()['actions'])
    key(1);record('cancel install does nothing',not state()['actions'] and state()['pending']=='')
    key(28);key(15);key(28);record('confirmed install routes exactly once',state()['actions']==['install'])
    ipc('pluginsProbe','busy','true');ipc('pluginsProbe','activate');record('busy blocks new action',state()['pending']=='' and state()['actions']==['install']);ipc('pluginsProbe','busy','false')
    key(2,'alt');wait(lambda:state()['tab']=='installed','Alt1 installed')
    ipc('pluginsProbe','preview');wait(lambda:state()['pending']=='update','update preview')
    record('update requires confirmation after preview',state()['actions']==['install']);key(1)
    ipc('pluginsProbe','longDiff');time.sleep(.15);v=state()
    record('long diff keeps confirmation buttons inside modal',v['modalButtons']['y']>=v['modal']['y'] and v['modalButtons']['y']+v['modalButtons']['h']<=v['modal']['y']+v['modal']['h'])
    key(109);record('long diff keyboard scroll works',state()['modalY']>0);shot('long-diff');key(1)
    key(4,'alt');wait(lambda:state()['tab']=='porting','Alt3 porting');shot('porting')
    record('Porting Lab retains usable body and footer',state()['footer']['y']+state()['footer']['h']<=state()['height'])
    ipc('pluginsProbe','tab','installed');ipc('pluginsProbe','empty');ipc('pluginsProbe','error');time.sleep(.2);shot('error')
    record('empty error view retains Close and geometry',state()['count']==0 and state()['footer']['y']+state()['footer']['h']<=state()['height'])
    key(1);wait(lambda:not mapped(),'Escape closes')
    wait(lambda:underlying()['focused'],'focus returns')
    record('Escape closes and restores focus without key leak',not underlying()['keys'])
    ipc('plugins','developer');wait(lambda:state()['search'],'reopen focus')
    record('reopen resets search and selection',state()['selected']==0 and state()['query']=='')
    pointer('move',2,args.height-2,'pause',100,'click',272,'pause',250)
    wait(lambda:not mapped(),'outside click closes')
    record('outside click closes manager',not mapped())
    log=Path('/work/shell.log').read_text()
    record('no QML runtime errors',not any(x in log for x in ['ReferenceError','TypeError','Binding loop','Error loading QML']))
    print(json.dumps({'pluginsChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
