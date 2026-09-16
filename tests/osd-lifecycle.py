"""OSD display-only checks in a private Wayland session; no hardware changes."""
import json
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Services/Osd.qml';s=p.read_text();a=s.index('    readonly property int value:');b=s.index('    readonly property string label:',a)
    s=s[:a]+'    property int value: 0\n    property bool muted: false\n\n'+s[b:];p.write_text(s)
    p=shell/'Osd/Osd.qml';s=p.read_text().replace('import QtQuick\n','import QtQuick\nimport Quickshell.Io\n',1)
    pos=s.index('        TextMetrics {');s=s[:pos]+'''
        IpcHandler {
            target:"osdProbe"
            function state():string {return JSON.stringify({visible:win.visible,showing:Osd.showing,
                x:box.x,y:box.y,w:box.width,h:box.height,windowH:win.height,top:Config.edge==="bottom",
                glyph:win.symbol,value:Osd.value,progress:meter.position,muted:Osd.muted,
                barWidth:meter.width,kind:Osd.kind,pill:win.takenByPill});}
            function display(kind:string,value:int,muted:bool):void {Osd.value=value;Osd.muted=muted;Osd.show(kind);}
            function stop():void {Osd.showing=false;}
            function setup():void {Config.setValues({osd:true,osdTimeout:650,mode:"bar",edge:"top",osdInPill:true});}
            function mode(value:string):void {Config.set("mode",value);}
            function edge(value:string):void {Config.set("edge",value);}
            function enabled(value:bool):void {Config.set("osd",value);}
            function suppress(audio:bool,control:bool):void {Runtime.audioPanelOpen=audio;Runtime.controlOpen=control;}
        }
''' +s[pos:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('osdProbe','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/osd-results.json').write_text(json.dumps(results,indent=2));assert ok,name
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','90000'],'osd-seat.log')
    target=Path('/work/osd-input-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
ShellRoot {
 property int clicks:0
 property var received:[]
 PanelWindow {visible:true;anchors {top:true;bottom:true;left:true;right:true}
 color:"#24283b";exclusionMode:ExclusionMode.Ignore
 WlrLayershell.layer:WlrLayer.Bottom
 WlrLayershell.keyboardFocus:WlrKeyboardFocus.Exclusive
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}
 MouseArea {anchors.fill:parent;onClicked:clicks++}}
 }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focus:sink.activeFocus,clicks:clicks,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'osd-input-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focus':False}
    wait(lambda:underlying()['focus'],'underlying focus')
    ipc('osdProbe','setup');time.sleep(.3)
    def show(kind,value,muted=False):
        ipc('osdProbe','display',kind,str(value),'true' if muted else 'false');time.sleep(.08)
    def shot(name):run(['grim','/work/osd-'+name+'.png'])
    show('volume',9);v=state();width=v['w'];bar=v['barWidth'];shot('volume')
    record('volume is visible and fits output',v['visible'] and v['x']>=0 and v['x']+v['w']<=args.width and 0<=v['progress']<=1)
    show('volume',100);record('percentage and glyph thresholds keep geometry stable',state()['w']==width and state()['barWidth']==bar and state()['progress']==1);shot('full')
    show('volume',55,True);record('mute uses zero fill and readable state',state()['progress']==0 and state()['muted']);shot('muted')
    show('mic',72);record('microphone kind and meter preserved',state()['kind']=='mic' and abs(state()['progress']-.72)<.01);shot('mic')
    show('brightness',43);record('brightness kind and meter preserved',state()['glyph']=='󰍹' and abs(state()['progress']-.43)<.01);shot('brightness')
    show('volume',135);record('over-amplification clamps meter',state()['progress']==1 and state()['value']==135)
    show('volume',-5);record('negative input never inverts meter',state()['progress']==0)
    show('volume',50);v=state();y=v['y']+(0 if v['top'] else args.height-v['windowH'])+v['h']/2
    pointer('move',round(v['x']+v['w']/2),round(y),'pause',100,'click',272,'pause',100,'tap',30)
    record('OSD remains click-through and does not steal keyboard focus',underlying()['clicks']==1 and len(underlying()['keys'])==1 and underlying()['focus'])
    show('volume',60);time.sleep(.4);show('volume',65);time.sleep(.35)
    record('repeated update restarts timeout',state()['visible'])
    wait(lambda:not state()['visible'],'OSD expires');record('timeout hides OSD',not state()['showing'])
    ipc('osdProbe','suppress','true','false');show('volume',20);record('audio panel suppresses volume OSD',not state()['showing'])
    show('mic',20);record('audio panel suppresses mic OSD',not state()['showing'])
    ipc('osdProbe','suppress','false','true');show('brightness',20);record('control panel suppresses brightness OSD',not state()['showing'])
    ipc('osdProbe','suppress','false','false');ipc('osdProbe','enabled','false');time.sleep(.2);show('volume',20);record('disabled setting suppresses OSD',not state()['showing'])
    ipc('osdProbe','enabled','true');ipc('osdProbe','mode','pill');time.sleep(.2);show('volume',20);record('pill owns display without duplicate OSD',state()['pill'] and state()['showing'] and not state()['visible'])
    ipc('osdProbe','mode','bar');ipc('osdProbe','edge','bottom');time.sleep(.2);show('volume',50);shot('top')
    record('bottom bar places OSD on opposite top edge',state()['top'] and state()['visible'] and state()['y']>=0)
    log=Path('/work/shell.log').read_text();record('no QML runtime errors',not any(x in log for x in ['ReferenceError','TypeError','Binding loop','Error loading QML']))
    print(json.dumps({'osdChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
