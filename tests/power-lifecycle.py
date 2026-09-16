"""Native battery panel + real tuned Process contract, private fake executable only."""
import json
import os
from pathlib import Path
import re
import time


def instrument(shell):
    bindir=Path('/work/power-bin');bindir.mkdir()
    fake=bindir/'tuned-adm'
    fake.write_text('''#!/bin/sh
case "$1" in
 active) printf 'Current active profile: '; cat /work/power-active ;;
 profile) printf '%s\\n' "$2" >> /work/power-actions
          sleep 0.5
          [ ! -e /work/power-fail ] || exit 1
          printf '%s\\n' "$2" > /work/power-active ;;
 *) exit 2 ;;
esac
''')
    fake.chmod(0o755)
    os.environ['PATH']=str(bindir)+':'+os.environ['PATH']
    Path('/work/power-active').write_text('balanced\n')
    Path('/work/power-fail').touch()
    p=shell/'Services/PowerService.qml';s=p.read_text()
    s=s.replace('readonly property var device: UPower.displayDevice','property var device: null')
    s=s.replace('readonly property bool onBattery: UPower.onBattery','property bool onBattery: true')
    s=s.replace('running: true','running: false')
    s=s.replace('["tuned-adm",','["/work/power-bin/tuned-adm",')
    s=re.sub(r'    function warn\(level\) \{.*?\n    }','    function warn(level) {}',s,flags=re.S)
    s=s.replace('    id: root','''    id: root
    function scenario(mode) {
        onBattery=!["charging","full","plugged"].includes(mode);
        device=mode==="absent" ? null : ({isLaptopBattery:true,
            percentage:mode==="zero" ? 0 : mode==="low" ? .05 : mode==="full" ? 1 : .64,
            state:mode==="charging" ? UPowerDeviceState.Charging : mode==="full" ? UPowerDeviceState.FullyCharged : UPowerDeviceState.Discharging,
            timeToEmpty:7200,timeToFull:3600,changeRate:mode==="full" || mode==="plugged" ? 0 : 12.3,healthPercentage:93});
    }
    Component.onCompleted: scenario("normal")
''',1);p.write_text(s)
    p=shell/'Services/Bt.qml';s=p.read_text()
    rows=[dict(name=n,connected=True,batteryAvailable=True,battery=v) for n,v in [('Headphones',.72),('Mouse',.12),('Keyboard',.9)]]
    rows.append(dict(name='No report',connected=True,batteryAvailable=False))
    s=s.replace('readonly property var devices: adapter?.devices?.values ?? []','property var devices: '+json.dumps(rows))
    start=s.index('    onWithBatteryChanged:');end=s.index('    function label',start)
    s=s[:start]+s[end:];p.write_text(s)
    p=shell/'Services/Kdeconnect.qml';s=p.read_text()
    s=s.replace('Config.value("kdeconnect", true)','false')
    rows=[dict(name='Phone <b>literal</b>' if i==0 else 'Phone '+str(i),paired=True,reachable=True,capabilities={'battery':True},charge=52+i,charging=i==0) for i in range(9)]
    rows.extend([dict(name='Excluded',paired=False,reachable=True,capabilities={'battery':True},charge=66),dict(name='Offline',paired=True,reachable=False,capabilities={'battery':True},charge=80)])
    s=s.replace('property var devices: []','property var devices: '+json.dumps(rows));p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"powerProbe"
        function panel():var {
            let p=Runtime.activePopout?.initialFocusTarget();
            while(p && !("extraBatteries" in p))p=p.parent;
            return p;
        }
        function state():string {
            const p=panel(),f=Runtime.activePopout?.focusWindow?.activeFocusItem;
            const pos=f ? f.mapToItem(null,0,0) : Qt.point(0,0);
            return JSON.stringify({visible:!!Runtime.activePopout?.visible,
                focus:f ? (f.accessibleName || f.Accessible.name) : "",
                x:pos.x,y:pos.y,fw:f?.width || 0,fh:f?.height || 0,
                width:Runtime.activePopout?.width || 0,height:Runtime.activePopout?.height || 0,
                profile:PowerService.activeProfile,busy:PowerService.profileBusy,error:PowerService.profileError,
                status:p?.batteryStatus || "",extras:p?.extraBatteries.length || 0,missing:p?.missingReports || 0,
                percent:PowerService.percent,power:PowerService.powerText});
        }
        function focus(name:string):void {
            const p=panel();if(!p)return;
            const f=p.focusTargets().find(i=>(i.accessibleName || i.Accessible.name).startsWith(name));
            if(f)f.forceActiveFocus(Qt.TabFocusReason);
        }
        function scenario(mode:string):void {PowerService.scenario(mode);}
        function extras(mode:string):void {
            Bt.devices=mode==="none" ? [] : Bt.devices;
            Kdeconnect.devices=mode==="none" ? [] : Kdeconnect.devices.slice(0,1);
        }
        function attempt(name:string):bool {return PowerService.setProfile(name);}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    target=Path('/work/power-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Power focus test"
  Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}
 }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}
''')
    launch(['/test-bin/qs','-p',str(target)],'power-focus-target.log')
    def underlying():
        res=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(res.stdout) if res.returncode==0 else {'focused':False,'keys':[]}
    def state():return json.loads(ipc('powerProbe','state'))
    def focus(name):ipc('powerProbe','focus',name)
    def actions():return Path('/work/power-actions').read_text().splitlines() if Path('/work/power-actions').exists() else []
    wait(lambda:underlying()['focused'],'underlying window')
    commands=['move',round(args.width-40*args.scale),round(13*args.scale),'pause',1200,'click',272,'pause',2000]
    # Selection navigation must not change the profile. Failure, retry, then
    # keyboard scroll through extra read-only devices and Escape focus return.
    for key,delay in [(106,1000),(28,2000),(28,2000),(105,800),(105,800),(28,2000),(108,1500),(1,1000),(30,500)]:
        commands+=['tap',key,'pause',delay]
    keys=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands)],'power-keyboard.log')
    processes.remove(keys);results={}
    try:
        wait(lambda:state()['visible'] and state()['profile']=='balanced','power panel ready')
        # Pointer starts over bar; initial keyboard target is selected profile.
        assert state()['focus']=='Balanced',state()
        assert state()['extras']==12 and state()['missing']==1,state()
        run(['grim','/work/power-normal.png']);results['normal']=state()
        wait(lambda:state()['focus']=='Performance','Right selects next profile')
        assert state()['profile']=='balanced' and actions()==[],state()
        wait(lambda:state()['busy'],'Enter starts profile process')
        assert ipc('powerProbe','attempt','powersave').strip()=='false'
        assert ipc('powerProbe','attempt','invalid').strip()=='false'
        wait(lambda:state()['error']!='' and not state()['busy'],'Failed process is reported')
        assert state()['profile']=='balanced' and actions()==['throughput-performance'],state()
        results['failure']=state();run(['grim','/work/power-failure.png'])
        Path('/work/power-fail').unlink()
        wait(lambda:state()['profile']=='throughput-performance' and not state()['busy'],'Retry reads actual selected profile')
        assert state()['error']=='',state()
        wait(lambda:state()['focus']=='Balanced','Left moves without activating')
        assert state()['profile']=='throughput-performance',state()
        wait(lambda:state()['focus']=='Power saver','Left reaches power saver')
        wait(lambda:state()['profile']=='powersave' and not state()['busy'],'Canonical powersave readback')
        # Read-only rows must scroll into view and participate in native arrows.
        focus('Phone 7');wait(lambda:state()['focus'].startswith('Phone 8'),'Down reaches final device row')
        time.sleep(.15)
        last=state();assert last['y']>=0 and last['y']+last['fh']<=last['height'],last
        results['lastDevice']=last;run(['grim','/work/power-last-device.png'])
        wait(lambda:not state()['visible'],'Escape dismisses power panel')
        wait(lambda:underlying()['keys']==[65],'Only A returns to application')
        results['returned']=underlying();keys.wait(timeout=5)
        # Pointer-only phase after virtual keyboard has released the seat.
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(round(args.width-40*args.scale)),str(round(13*args.scale)),'pause','1200','click','272','pause','1200'])
        wait(lambda:state()['visible'],'Pointer reopens panel')
        focus('Balanced');time.sleep(.2);button=state()
        x=round(args.width-args.scale*button['width']+args.scale*(button['x']+button['fw']/2))
        y=round(args.scale*(31+button['y']+button['fh']/2))
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(x),str(y),'pause','150','click','272','pause','800'])
        wait(lambda:state()['profile']=='balanced','Pointer changes profile')
        results['actions']=actions()
        assert results['actions']==['throughput-performance','throughput-performance','powersave','balanced'],results
        results['states']={}
        for mode,expected in [('charging','CHARGING'),('full','FULLY CHARGED'),('plugged','PLUGGED IN'),('low','ON BATTERY'),('zero','ON BATTERY')]:
            ipc('powerProbe','scenario',mode);time.sleep(.2)
            s=state();assert s['status']==expected,s
            if mode=='zero':assert s['percent']==0,s
            if mode in ('full','plugged'):assert s['power']=='0.0 W',s
            results['states'][mode]=s
            run(['grim','/work/power-'+mode+'.png'])
        # Keep the executable path private even when deliberately missing.
        fake=Path('/work/power-bin/tuned-adm');saved=fake.with_name('disabled')
        fake.rename(saved)
        try:
            ipc('powerProbe','attempt','performance')
            wait(lambda:not state()['busy'] and 'Could not start' in state()['error'],'FailedToStart releases busy and reports failure')
            results['failedToStart']=state()
        finally:saved.rename(fake)
        ipc('powerProbe','attempt','balanced')
        wait(lambda:not state()['busy'] and state()['profile']=='balanced' and state()['error']=='','Recover from missing executable')
        ipc('powerProbe','extras','short')
        time.sleep(.2);run(['grim','/work/power-four-devices.png'])
        ipc('powerProbe','scenario','normal')
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(round((args.width-300*args.scale)/2+20*args.scale)),str(args.height//2),'pause','150','click','272','pause','200'])
        wait(lambda:not state()['visible'],'Outside application click dismisses')
        ipc('powerProbe','extras','none')
        Path('/work/power-active').write_text('custom-profile\n')
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(round(args.width-40*args.scale)),str(round(13*args.scale)),'pause','1200','click','272','pause','1200'])
        wait(lambda:state()['visible'] and state()['profile']=='custom-profile','Unknown profile is preserved')
        wait(lambda:state()['visible'] and state()['focus']=='Refresh power profile','Unknown profile focuses refresh')
        assert state()['extras']==0 and state()['missing']==0,state()
        results['unknown']=state();run(['grim','/work/power-unknown.png'])
        run(['/test-bin/pointer-client',str(args.width),str(args.height),'move',str(round((args.width-300*args.scale)/2+20*args.scale)),str(args.height//2),'pause','150','click','272','pause','200'])
        wait(lambda:not state()['visible'],'Dismiss unknown-profile panel')
        ipc('powerProbe','scenario','absent')
        assert state()['percent']==0 and not state()['visible'],state()
    finally:
        Path('/work/power-last-state.json').write_text(json.dumps({'panel':state(),'underlying':underlying()},indent=2))
        keys.wait(timeout=25)
    log=Path('/work/shell.log').read_text()
    assert not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log),log
    Path('/work/power-result.json').write_text(json.dumps(results,indent=2))
