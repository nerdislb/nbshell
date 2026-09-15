"""Native network panel contract with synthetic data, never host networking.

Instrument only the disposable copy inside wayland-lifecycle's private
Wayland/D-Bus/network namespace. Password contents never enter test receipts.
"""
import json
from pathlib import Path
import re
import time


def instrument(shell):
    p=shell/'Services/Net.qml';s=p.read_text()
    s=s.replace('readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null','property var wifiDevice: ({scannerEnabled:false})')
    s=s.replace('readonly property bool wifiEnabled: Networking.wifiEnabled','property bool wifiEnabled: true')
    s=s.replace('readonly property bool wiredConnected: wiredDevice?.connected ?? false','property bool wiredConnected: false')
    s=s.replace('readonly property var activeWifi: (wifiDevice?.networks?.values ?? []).find(n => n.connected) ?? null','readonly property var activeWifi: wifiNetworks.find(n=>n.connected) ?? null')
    s=s.replace('readonly property var wifiNetworks: WifiRows.rows(wifiDevice?.networks?.values ?? [])','property var wifiNetworks: []')
    s=s.replace('readonly property bool connectivityChecksEnabled: Networking.backend === NetworkBackendType.NetworkManager\n        && Networking.canCheckConnectivity && Networking.connectivityCheckEnabled','readonly property bool connectivityChecksEnabled: true')
    # Replace the complete multi-line enum binding, leaving portal/restricted
    # derivations on the real production code path.
    start=s.index('    readonly property string connectivity:');end=s.index('    readonly property bool hasCaptivePortal:',start)
    s=s[:start]+'    property string connectivity: "full"\n'+s[end:]
    replacements={
        'refreshConnectivity()':'function refreshConnectivity() { lastAction="check"; }',
        'openCaptivePortal()':'function openCaptivePortal() { lastAction="portal"; }',
        'refreshVpns()':'function refreshVpns() {}',
        'toggleVpn(profile)':'function toggleVpn(profile) { lastAction="vpn:"+profile.uuid; }',
        'setTrafficMonitoring(value)':'function setTrafficMonitoring(value) { trafficMonitoring=value; }',
        'connect(row, psk)':'function connect(row, psk) { lastAction="connect:"+row.key; passwordLength=psk.length; }',
        'disconnect(row)':'function disconnect(row) { lastAction="disconnect:"+row.key; }',
        'setWifiEnabled(value)':'function setWifiEnabled(value) { wifiEnabled=value; lastAction="radio:"+value; }',
        'setScanner(value)':'function setScanner(value) { scannerWanted=value; }',
        'rescan()':'function rescan() { lastAction="scan"; }',
    }
    for signature,body in replacements.items():
        s=re.sub(r'    function '+re.escape(signature)+r' \{.*?\n    }','    '+body,s,flags=re.S)
    # Prevent the test fixture from spawning even isolated network helpers.
    s=s.replace('running: root.trafficMonitoring','running: false && root.trafficMonitoring')
    fixture='''
    property string lastAction: ""
    property int passwordLength: 0
    property bool scannerWanted: false
    function scenario(mode) {
        wifiEnabled=mode!=="off";
        wifiDevice=mode==="no-adapter" ? null : ({scannerEnabled:false});
        connectivity=mode==="portal" ? "portal" : "full";
        const rows=[];
        const names=["Home Wi-Fi","Saved office","Cafe locked","Guest open","Long external SSID <b>not markup</b>"];
        for(let i=0;i<14;i++) {
            const name=names[i] || "Neighbour "+String(i).padStart(2,"0");
            const security=i===3 ? WifiSecurityType.Open : WifiSecurityType.Wpa2Psk;
            rows.push({name:name,key:JSON.stringify([name,security]),security:security,connected:i===0,known:i<2,signalStrength:0.95-i*0.04});
        }
        wifiNetworks=mode==="empty" || mode==="off" || mode==="no-adapter" ? [] : rows;
        vpnAvailable=true;
        vpnProfiles=[{name:"Work VPN",uuid:"fixture-vpn",type:"wireguard",active:false}];
        trafficInterface="wlan-test";downloadBps=32768;uploadBps=2048;
    }
    function resnapshot() { wifiNetworks=wifiNetworks.map(n=>Object.assign({},n,{signalStrength:n.signalStrength*0.99})); }
    function removePending(key) { wifiNetworks=wifiNetworks.filter(n=>n.key!==key); }
    Component.onCompleted: scenario("normal")
'''
    s=s.replace('    id: root','    id: root\n'+fixture,1);p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"networkProbe"
        function panel():var {
            let item=Runtime.activePopout ? Runtime.activePopout.initialFocusTarget() : null;
            while(item && !("pendingNetwork" in item)) item=item.parent;
            return item;
        }
        function state():string {
            const popup=Runtime.activePopout;
            const p=panel();
            const focused=popup?.focusWindow?.activeFocusItem;
            const point=focused ? focused.mapToItem(null,0,0) : Qt.point(0,0);
            return JSON.stringify({visible:!!popup?.visible,keyboard:!!popup?.takesKeyboard,
                width:popup?.width || 0,height:popup?.height || 0,
                focus:focused ? (focused.accessibleName || focused.Accessible.name) : "", focusObject:focused ? String(focused) : "",
                focusY:point.y,focusHeight:focused ? focused.height : 0,
                rowCount:p ? p.shownNetworks.length : 0,
                pending:p ? p.pendingNetwork : "",passwordLength:p ? p.passwordText.length : 0,
                action:Net.lastAction,submittedLength:Net.passwordLength,
                scanner:Net.scannerWanted,traffic:Net.trafficMonitoring,
                controls:p ? p.controls(p,[]).map(c=>c.Accessible.name) : []});
        }
        function focus(name:string):void {
            const p=panel();
            const c=p ? p.controls(p,[]).find(c=>c.Accessible.name===name) : null;
            if(c)c.forceActiveFocus(Qt.TabFocusReason);
        }
        function resnapshot():void { Net.resnapshot(); }
        function removePending():void { const p=panel(); if(p) Net.removePending(p.pendingNetwork); }
        function scenario(mode:string):void { Net.scenario(mode); }
    }
'''+s[end:];p.write_text(s)


def exercise(run, launch, wait, ipc, processes, shell, args):
    target=Path('/work/network-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Network focus test"
  Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}
 }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}
''')
    launch(['/test-bin/qs','-p',str(target)],'network-focus-target.log')
    def focus():
        res=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(res.stdout) if res.returncode==0 else {'focused':False,'keys':[]}
    def state():return json.loads(ipc('networkProbe','state'))
    wait(lambda:focus()['focused'],'network underlying window')
    # One persistent seat keyboard; coordinate target is the sole NET widget.
    commands=['move',round(args.width-15*args.scale),round(13*args.scale),'pause',1200,'click',272,'pause',1800]
    events=[28,30,1,28,30,28,28,30,28,28,28,28,1,30]
    for key in events:commands += ['tap',key,'pause',1400]
    keys=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands),'pause','1000'],'network-keyboard.log')
    processes.remove(keys)
    results={}
    try:
        wait(lambda:state()['keyboard'] and state()['focus']=='Home Wi-Fi','network initial focus')
        initial=state();results['initial']=initial
        assert initial['rowCount']==14,initial
        assert initial['width']<=args.width/args.scale and initial['height']<args.height/args.scale,initial
        time.sleep(.2);run(['grim','/work/network-normal.png'])
        ipc('networkProbe','focus','Neighbour 13')
        time.sleep(.1)
        last=state();assert last['focus']=='Neighbour 13' and last['focusY']>=0 and last['focusY']+last['focusHeight']<=last['height'],last
        results['lastNetwork']=last
        run(['grim','/work/network-last-row.png'])
        ipc('networkProbe','focus','Cafe locked')
        wait(lambda:state()['focus']=='Wi-Fi password','Enter opens password')
        wait(lambda:state()['passwordLength']==1,'A enters masked password')
        ipc('networkProbe','resnapshot')
        time.sleep(.15)
        after=state();assert after['passwordLength']==1 and after['focus']=='Wi-Fi password',after
        run(['grim','/work/network-password.png'])
        wait(lambda:state()['pending']=='','Escape cancels password, not panel')
        assert state()['visible'] and state()['passwordLength']==0,state()
        wait(lambda:state()['focus']=='Wi-Fi password','Enter reopens password')
        wait(lambda:state()['passwordLength']==1,'A enters replacement password')
        wait(lambda:state()['submittedLength']==1,'Enter submits credential to selected network')
        results['credential']=state();assert 'Cafe locked' in state()['action'],state()
        ipc('networkProbe','focus','Cafe locked')
        wait(lambda:state()['focus']=='Wi-Fi password','Enter opens editor for disappearing network')
        wait(lambda:state()['passwordLength']==1,'Enter credential before disappearance')
        ipc('networkProbe','removePending')
        wait(lambda:state()['pending']=='' and state()['passwordLength']==0,'Disappearing network clears credential')
        assert state()['visible'],state()
        ipc('networkProbe','scenario','normal')
        ipc('networkProbe','focus','Guest open')
        wait(lambda:'Guest open' in state()['action'],'Enter connects open network without password')
        ipc('networkProbe','focus','Home Wi-Fi')
        wait(lambda:state()['action'].startswith('disconnect:'),'Enter disconnects selected connected network')
        ipc('networkProbe','scenario','portal')
        ipc('networkProbe','focus','Sign in to network')
        run(['grim','/work/network-portal.png'])
        wait(lambda:state()['action']=='portal','Enter opens captive portal action')
        ipc('networkProbe','focus','Work VPN')
        wait(lambda:state()['action']=='vpn:fixture-vpn','Enter activates preserved VPN')
        results['actions']=state()
        ipc('networkProbe','focus','Home Wi-Fi')
        ipc('networkProbe','scenario','no-adapter')
        wait(lambda:state()['focus']=='Turn Wi-Fi off','Missing adapter keeps a guarded focus target')
        time.sleep(.2);run(['grim','/work/network-no-adapter.png'])
        wait(lambda:not state()['visible'],'Escape dismisses network panel')
        wait(lambda:focus()['keys']==[65],'Only A returns to underlying window')
        final=state();assert not final['scanner'] and not final['traffic'],final
        results['closed']=final;results['returned']=focus()
    finally:
        Path('/work/network-last-state.json').write_text(json.dumps(state(),indent=2))
        keys.wait(timeout=15)
    log=Path('/work/shell.log').read_text()
    assert not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log),log
    Path('/work/network-result.json').write_text(json.dumps(results,indent=2))
