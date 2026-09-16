"""Production Bluetooth UI on a private seat; no host BlueZ or network bus."""
import json
from pathlib import Path
import re
import runpy
import time


def instrument(shell):
    # Retain the proven network probe and deterministic companion content.
    runpy.run_path('/source/tests/network-lifecycle.py')['instrument'](shell)
    p=shell/'Services/Bt.qml';s=p.read_text()
    s=s.replace('readonly property var adapter: Bluetooth.defaultAdapter','property var adapter: ({})')
    s=s.replace('readonly property bool enabled: adapter?.enabled ?? false','property bool enabled: true')
    s=s.replace('readonly property bool discovering: adapter?.discovering ?? false','property bool discovering: false')
    s=s.replace('readonly property var devices: adapter?.devices?.values ?? []','property var devices: []')
    replacements={
        'setEnabled(value)':'function setEnabled(value) { enabled=value; if(!value) discovering=false; lastAction="radio:"+value; }',
        'pairWithAgent(device)':'function pairWithAgent(device) { lastAction="pair:"+device.address; pairingAddress=device.address; actionCount++; lastGeneration=device.generation; }',
        'forgetDevice(device)':'function forgetDevice(device) { lastAction="forget:"+device.address; actionCount++; lastGeneration=device.generation; devices=devices.filter(d=>d.address!==device.address); }',
        'scan(value)':'function scan(value) { requested=value; discovering=value; lastAction="scan:"+value; }',
    }
    for signature,body in replacements.items():
        s,n=re.subn(r'^    function '+re.escape(signature)+r' \{.*?\n    }','    '+body,s,flags=re.S|re.M)
        assert n==1,signature
    start=s.index('    onWithBatteryChanged:');end=s.index('    function label',start)
    s=s[:start]+s[end:]
    fixture='''
    property string lastAction: ""
    property int actionCount: 0
    property int generation: 0
    property int lastGeneration: -1
    function scenario(mode) {
        enabled=mode!=="off";
        adapter=mode==="no-adapter" ? null : ({});
        discovering=mode==="scan";
        requested=false; pairingAddress=""; pairingError="";
        generation++;
        const names=["Headphones","Keyboard","Mouse","Speaker <b>literal</b>"];
        const list=[];
        if(mode!=="empty" && mode!=="off" && mode!=="no-adapter") for(let i=0;i<12;i++) {
            const address="00:11:22:33:44:"+String(i).padStart(2,"0");
            list.push({address:address,name:names[i] || "Nearby "+String(i).padStart(2,"0"),
                connected:i===0,paired:i<3,bonded:i<3,pairing:false,
                batteryAvailable:i===0,battery:.72,generation:root.generation,
                connect:function(){root.lastAction="connect:"+this.address;root.actionCount++;root.lastGeneration=this.generation;},
                disconnect:function(){root.lastAction="disconnect:"+this.address;root.actionCount++;root.lastGeneration=this.generation;}});
        }
        devices=list;
    }
    function resnapshot() { generation++; devices=devices.map(d=>Object.assign({},d,{generation:root.generation})); }
    function disappear(address) { devices=devices.filter(d=>d.address!==address); }
    Component.onCompleted: scenario("normal")
'''
    s=s.replace('    id: root','    id: root\n'+fixture,1);p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"bluetoothProbe"
        function section():var {
            function find(item) {
                if(!item)return null;
                if("pendingRemoval" in item) return item;
                for(let child of item.children){const found=find(child);if(found)return found;}
                return null;
            }
            let item=Runtime.activePopout?.initialFocusTarget();
            while(item && !("pendingNetwork" in item)) item=item.parent;
            return find(item);
        }
        function state():string {
            const b=section();
            const f=Runtime.activePopout?.focusWindow?.activeFocusItem;
            const p=f ? f.mapToItem(null,0,0) : Qt.point(0,0);
            return JSON.stringify({visible:!!Runtime.activePopout?.visible,
                focus:f ? (f.accessibleName || f.Accessible.name) : "",
                focusX:p.x,focusY:p.y,focusWidth:f?.width || 0,focusHeight:f?.height || 0,width:Runtime.activePopout?.width || 0,height:Runtime.activePopout?.height || 0,
                count:b?.shownDevices.length || 0,pending:b?.pendingRemoval || "",
                action:Bt.lastAction,actions:Bt.actionCount,generation:Bt.generation,lastGeneration:Bt.lastGeneration,
                requested:Bt.requested,enabled:Bt.enabled});
        }
        function resnapshot():void {Bt.resnapshot();}
        function scenario(mode:string):void {Bt.scenario(mode);}
        function disappear(address:string):void {Bt.disappear(address);}
        function pairingDone():void {Bt.pairingAddress="";}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    target=Path('/work/bluetooth-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Bluetooth focus test"
  Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}
 }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}
''')
    launch(['/test-bin/qs','-p',str(target)],'bluetooth-focus-target.log')
    def underlying():
        res=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(res.stdout) if res.returncode==0 else {'focused':False,'keys':[]}
    def state():return json.loads(ipc('bluetoothProbe','state'))
    def focus(name):ipc('networkProbe','focus',name)
    wait(lambda:underlying()['focused'],'Bluetooth underlying window')
    commands=['move',round(args.width-15*args.scale),round(13*args.scale),'pause',1200,'click',272,'pause',2500]
    # Disconnect, connect, pair, start/stop scan, forget/cancel/confirm, off,
    # Escape to close, one A returned to the underlying application.
    for key in [28,28,28,28,28,28,1,28,28,28,1,30]:commands+=['tap',key,'pause',1800]
    keys=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands)],'bluetooth-keyboard.log')
    processes.remove(keys);results={}
    try:
        wait(lambda:state()['visible'] and state()['count']==12,'Bluetooth panel ready')
        focus('Headphones');time.sleep(.25);run(['grim','/work/bluetooth-normal.png'])
        wait(lambda:state()['action']=='disconnect:00:11:22:33:44:00','Enter disconnects actual device')
        focus('Keyboard');ipc('bluetoothProbe','resnapshot')
        wait(lambda:state()['focus']=='Keyboard','Scan snapshot preserves selected address')
        wait(lambda:state()['action']=='connect:00:11:22:33:44:01','Enter connects paired device')
        assert state()['lastGeneration']==state()['generation'],state()
        focus('Nearby 11');time.sleep(.2)
        last=state();assert last['focus']=='Nearby 11' and last['focusY']>=0 and last['focusY']+last['focusHeight']<=last['height'],last
        results['lastDevice']=last;run(['grim','/work/bluetooth-last-device.png'])
        wait(lambda:state()['action']=='pair:00:11:22:33:44:11','Enter pairs new device')
        ipc('bluetoothProbe','pairingDone')
        focus('Scan for devices')
        wait(lambda:state()['requested'],'Enter starts our scan')
        wait(lambda:not state()['requested'],'Enter stops our scan')
        focus('Keyboard');focus('Forget Keyboard')
        before=state()['actions']
        wait(lambda:state()['pending']!='','First forget activation asks for confirmation')
        assert state()['actions']==before,state()
        run(['grim','/work/bluetooth-confirm.png'])
        wait(lambda:state()['pending']=='','Escape cancels forget')
        assert state()['visible'] and state()['actions']==before,state()
        wait(lambda:state()['pending']!='','Second attempt asks again')
        ipc('bluetoothProbe','resnapshot')
        wait(lambda:state()['focus']=='Confirm forget Keyboard','Confirmation survives discovery refresh')
        wait(lambda:state()['action']=='forget:00:11:22:33:44:01','Confirmed action forgets only selected address')
        assert state()['actions']==before+1 and state()['lastGeneration']==state()['generation'],state()
        wait(lambda:state()['focus']=='Turn Bluetooth off','Removed selection falls back to radio')
        results['forgot']=state()
        wait(lambda:not state()['enabled'],'Enter disables radio')
        run(['grim','/work/bluetooth-off.png'])
        ipc('bluetoothProbe','scenario','empty')
        run(['grim','/work/bluetooth-empty.png'])
        ipc('bluetoothProbe','scenario','no-adapter')
        run(['grim','/work/bluetooth-no-adapter.png'])
        wait(lambda:not state()['visible'],'Escape dismisses combined panel')
        wait(lambda:underlying()['keys']==[65],'Only A returns to underlying window')
        assert not state()['requested'],state()
        results['returned']=underlying()
        # Finish the one-keyboard seat before pointer-only lifecycle checks.
        keys.wait(timeout=5)
        ipc('bluetoothProbe','scenario','normal')
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(round(args.width-15*args.scale)),str(round(13*args.scale)),'pause','1200','click','272','pause','1200'])
        wait(lambda:state()['visible'] and state()['count']==12,'Pointer opens Bluetooth-containing panel')
        # Real pointer hits on the sibling forget action must not connect a row.
        focus('Mouse');focus('Forget Mouse');time.sleep(.2)
        button=state()
        x=round(args.width-args.scale*button['width']+args.scale*(button['focusX']+button['focusWidth']/2))
        y=round(args.scale*(31+button['focusY']+button['focusHeight']/2))
        command=['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(x),str(y),'pause','150','click','272','pause','250']
        before=state()['actions'];run(command)
        wait(lambda:state()['pending']=='00:11:22:33:44:02','Pointer requests forget confirmation')
        assert state()['actions']==before,state()
        run(command)
        wait(lambda:state()['action']=='forget:00:11:22:33:44:02','Pointer confirms forget')
        assert state()['actions']==before+1,state()
        results['pointerForget']=state()
        ipc('bluetoothProbe','scenario','normal')
        focus('Mouse');focus('Forget Mouse');run(command)
        wait(lambda:state()['pending']=='00:11:22:33:44:02','Pointer requests second confirmation')
        ipc('bluetoothProbe','disappear','00:11:22:33:44:02')
        wait(lambda:state()['pending']=='' and state()['focus']=='Turn Bluetooth off','Disappearing device clears confirmation and restores focus')
        assert state()['actions']==before+1,state()
        ipc('bluetoothProbe','scenario','normal')
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(round((args.width-300*args.scale)/2+20*args.scale)),str(args.height//2),'pause','150','click','272','pause','200'])
        wait(lambda:not state()['visible'],'Click on underlying application dismisses panel after pointer actions')
    finally:
        Path('/work/bluetooth-last-state.json').write_text(json.dumps({'panel':state(),'underlying':underlying()},indent=2))
        keys.wait(timeout=25)
    log=Path('/work/shell.log').read_text()
    assert not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log),log
    Path('/work/bluetooth-result.json').write_text(json.dumps(results,indent=2))
