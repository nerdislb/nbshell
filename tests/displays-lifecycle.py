"""Native display UI with a synthetic output service, never host display changes."""
import json
import time
from pathlib import Path


def instrument(shell):
    (shell/'Services/Displays.qml').write_text('''pragma Singleton
import QtQuick
import Quickshell
Singleton {
 property var outputs: []
 property bool loading: false
 property string error: ""
 property string selectedName: ""
 property var calls: []
 readonly property var selected: outputs.find(row=>row.name===selectedName) ?? (outputs[0] ?? null)
 function refresh() { calls=calls.concat([{kind:"refresh"}]); }
 function setValue(name,key,value) { calls=calls.concat([{kind:"set",name:name,key:key,value:value}]); }
 function place(name,relation,reference) { calls=calls.concat([{kind:"place",name:name,relation:relation,reference:reference}]); }
}''')
    p=shell/'Settings/DisplayPanel.qml';s=p.read_text();end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    function testFind(item,name) {
        if(item.visible && item.enabled && item.accessibleName===name) return item;
        for(const child of item.children ?? []) { const found=testFind(child,name);if(found)return found; }
        return null;
    }
    IpcHandler {
        target:"displayProbe"
        function rect(item:var):var {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
        function state():string {
            const f=keys.Window.window.activeFocusItem;
            return JSON.stringify({name:f?.accessibleName||f?.Accessible.name||"",focus:f?rect(f):{},
                footer:rect(footer),body:rect(body),height:root.height,scroll:body.contentY,
                selected:root.display?.name??"",resolution:root.resolutionOpen,
                toggleEnabled:toggleOutput.enabled,hint:outputHint.text,calls:Displays.calls});
        }
        function setup():void {
            const modes=Array.from({length:18},(_,i)=>({width:1920,height:1080,refresh:60+i,label:"1920x1080@"+(60+i),current:i===0,preferred:i===0}));
            Displays.outputs=[{name:"eDP-1",make:"Fixture",model:"Internal screen",width:1920,height:1080,scale:1,transform:"normal",enabled:true,focused:true,x:0,y:0,modes:modes,currentMode:modes[0].label},
              {name:"DP-2",make:"Long manufacturer name",model:"External monitor with a very long name that must wrap safely",width:2560,height:1440,scale:1.25,transform:"normal",enabled:true,focused:false,x:1920,y:0,modes:modes,currentMode:modes[0].label}];
            Displays.selectedName="eDP-1";Displays.error="";
        }
        function focus(name:string):bool {const i=root.testFind(keys,name);if(!i)return false;i.forceActiveFocus();return true;}
        function modeLast():void {modeButtons.itemAt(17).forceActiveFocus();}
        function toggle():void {toggleOutput.activate();}
        function disabledSecond():void {Displays.outputs=Displays.outputs.map((o,i)=>Object.assign({},o,{enabled:i===0}));Displays.selectedName="DP-2";}
        function single():void {Displays.outputs=Displays.outputs.slice(0,1);Displays.selectedName="eDP-1";}
        function empty():void {Displays.outputs=[];Displays.selectedName="";}
        function error():void {Displays.error="Fixture output query failed. ".repeat(8);}
        function loading(value:bool):void {Displays.loading=value;}
        function close():void {root.close();}
    }
''' +s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('displayProbe','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/displays-results.json').write_text(json.dumps(results,indent=2));assert ok,name
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','90000'],'displays-seat.log')
    def key(code,shift=False):pointer('pause',150,*(['mod','shift'] if shift else []),'tap',code,'pause',150)
    def shot(name):time.sleep(.15);run(['grim','/work/displays-'+name+'.png'])
    def focus(name):assert ipc('displayProbe','focus',name)=='true',name;time.sleep(.15)
    def visible():
        v=state();return v['focus']['y']>=v['body']['y']-1 and v['focus']['y']+v['focus']['h']<=v['body']['y']+v['body']['h']+1
    target=Path('/work/display-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Display focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'displays-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    def opened():return json.loads(ipc('state','dump'))['displays']
    wait(lambda:underlying()['focused'],'underlying focused')
    ipc('displays','open');wait(lambda:state()['name']=='Refresh','initial focus')
    ipc('displayProbe','setup');time.sleep(.2);shot('initial')
    record('initial focus on nonmutating refresh',state()['name']=='Refresh' and len(state()['calls'])>0 and all(c['kind']=='refresh' for c in state()['calls']))
    key(15);record('Tab reaches first output',state()['name']=='eDP-1 · focused')
    key(15);key(28);record('select other output without changing it',state()['selected']=='DP-2' and all(c['kind']=='refresh' for c in state()['calls']));shot('external')
    key(15);record('resolution control reachable',state()['name'].startswith('1920×1080'))
    key(28);record('mode expansion does not apply a mode',state()['resolution'] and all(c['kind']=='refresh' for c in state()['calls']))
    ipc('displayProbe','modeLast');time.sleep(.2);record('long mode list follows focus',visible());shot('modes')
    key(1);record('Escape collapses modes without closing',opened() and not state()['resolution'] and state()['name'].startswith('1920×1080'))
    key(28);ipc('displayProbe','modeLast');key(28)
    record('mode selected before delegate destruction',state()['calls'][-1]=={'kind':'set','name':'DP-2','key':'mode','value':'1920x1080@77'} and not state()['resolution'])
    focus('3×');record('scale action scrolls into view',visible());key(28)
    record('scale routes unchanged value',state()['calls'][-1]=={'kind':'set','name':'DP-2','key':'scale','value':3})
    focus('Right 90°');key(28);record('orientation routes unchanged value',state()['calls'][-1]['key']=='transform' and state()['calls'][-1]['value']=='270')
    focus('Mirror position');key(28);record('relative placement uses other output',state()['calls'][-1]=={'kind':'place','name':'DP-2','relation':'same','reference':'eDP-1'})
    focus('Turn off');record('output action and footer fit',visible() and state()['footer']['y']+state()['footer']['h']<=state()['height']);shot('output')
    key(28);record('multiple-output toggle keeps backend contract',state()['calls'][-1]=={'kind':'set','name':'DP-2','key':'enabled','value':False})
    key(15);record('fixed Close reachable',state()['name']=='Close')
    key(15,True);record('reverse Tab returns to output action',state()['name']=='Turn off' and visible())
    ipc('displayProbe','disabledSecond');time.sleep(.2)
    record('disabled output offers Turn on without last-output warning',state()['toggleEnabled'] and 'cannot' not in state()['hint'])
    focus('Turn on');key(28);record('disabled output can be enabled',state()['calls'][-1]=={'kind':'set','name':'DP-2','key':'enabled','value':True})
    ipc('displayProbe','single');time.sleep(.2);before=state()['calls'];ipc('displayProbe','toggle')
    record('last active output cannot be disabled',not state()['toggleEnabled'] and state()['calls']==before)
    ipc('displayProbe','empty');time.sleep(.2);shot('empty');record('hot unplug leaves usable focus',state()['name']=='Refresh' and not state()['toggleEnabled'])
    ipc('displayProbe','error');time.sleep(.2);shot('error');record('long error does not push footer offscreen',state()['footer']['y']+state()['footer']['h']<=state()['height'])
    key(63);record('F5 refresh works when empty',state()['calls'][-1]['kind']=='refresh')
    key(1);wait(lambda:not opened(),'Escape closes');wait(lambda:underlying()['focused'],'focus returns')
    record('Escape returns focus without leaking key',not underlying()['keys'])
    ipc('displays','open');wait(lambda:state()['name']=='Refresh','reopen')
    ipc('displayProbe','setup');focus('1920×1080  60 Hz  · preferred  ⌄');key(28)
    ipc('displays','close');wait(lambda:not opened(),'lifecycle close')
    ipc('displays','open');wait(lambda:state()['name']=='Refresh','lifecycle reopen')
    record('lifecycle reopen resets modes and refreshes',not state()['resolution'] and state()['calls'][-1]['kind']=='refresh')
    pointer('move',2,args.height-2,'pause',120,'click',272,'pause',200);wait(lambda:not opened(),'outside closes')
    record('outside click closes reopened panel',not opened())
    log=Path('/work/shell.log').read_text();record('no QML runtime errors',not any(x in log for x in ['ReferenceError','TypeError','Binding loop','Error loading QML']))
    print(json.dumps({'displayChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
