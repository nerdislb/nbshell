"""Audio parity on a private Wayland seat and in-memory audio nodes only.

Host PipeWire/system bus/network are never mounted by wayland-lifecycle.py.
Only the disposable shell copy is instrumented; production has no fixture IPC.
"""
import json
from pathlib import Path
import re
import time


def instrument(shell):
    p = shell / 'Services/Audio.qml'
    s = p.read_text()
    fixture = '''
    QtObject { id: speakers; property string name: "Built-in speakers"; property QtObject audio: QtObject { property real volume: 0.45; property bool muted: false } }
    QtObject { id: headphones; property string name: "Bluetooth headphones"; property QtObject audio: QtObject { property real volume: 0.60; property bool muted: false } }
    QtObject { id: mic; property string name: "Internal microphone"; property QtObject audio: QtObject { property real volume: 0.65; property bool muted: false } }
    QtObject { id: usbMic; property string name: "USB microphone"; property QtObject audio: QtObject { property real volume: 0.50; property bool muted: false } }
    QtObject { id: music; property string name: "Music player"; property QtObject audio: QtObject { property real volume: 0.70; property bool muted: false } }
    QtObject { id: browser; property string name: "Browser with an intentionally very long external title <b>literal text</b>"; property QtObject audio: QtObject { property real volume: 0.35; property bool muted: true } }
    function scenario(mode) {
        sink = mode === "empty" ? null : speakers;
        source = mode === "empty" ? null : mic;
        sinks = mode === "empty" ? [] : [speakers, headphones];
        sources = mode === "empty" ? [] : [mic, usbMic];
        appStreams = mode === "empty" ? [] : [music, browser];
        routes = mode === "extras" ? [{name:"Music player", sinkLabel:"Built-in speakers", sink:"speakers", index:1}] : [];
        routeSinks = mode === "extras" ? [{name:"speakers"},{name:"headphones"}] : [];
        btKarte = mode === "extras" ? "fixture" : "";
        btGeraet = "Bluetooth headphones with an intentionally very long label";
        btAktiv = "sbc"; btBeste = "aac";
        btCodecs = [{codec:"AAC",profil:"aac"},{codec:"SBC",profil:"sbc"}];
    }
    property string lastRoute: ""
    property string lastCodec: ""
    Component.onCompleted: scenario("basic")
'''
    s=s.replace('    id: root', '    id: root\n'+fixture, 1)
    s=s.replace('readonly property var sink: Pipewire.defaultAudioSink','property var sink: speakers')
    s=s.replace('readonly property var source: Pipewire.defaultAudioSource','property var source: mic')
    s=s.replace('readonly property var sinks: AudioNodes.uniqueSinks(Pipewire.nodes.values, sink)', 'property var sinks: [speakers, headphones]')
    s=re.sub(r'    readonly property var appStreams:.*?\n\n', '    property var appStreams: [music, browser]\n\n', s, flags=re.S)
    s=re.sub(r'    readonly property var sources:.*?\n\n    readonly property int micVolume:', '    property var sources: [mic, usbMic]\n    readonly property real micPeak: 0.25\n\n    readonly property int micVolume:', s, flags=re.S)
    s=s.replace('Pipewire.preferredDefaultAudioSink = node','root.sink = node').replace('Pipewire.preferredDefaultAudioSource = node','root.source = node')
    s=re.sub(r'    function codecsLesen\(\) \{.*?\n    }','    function codecsLesen() {}',s,flags=re.S)
    s=re.sub(r'    function routenLesen\(\) \{.*?\n    }','    function routenLesen() {}',s,flags=re.S)
    s=re.sub(r'    function cycleRoute\(stream\) \{.*?\n    }','    function cycleRoute(stream) { lastRoute = stream.name; }',s,flags=re.S)
    s=re.sub(r'    function setzeCodec\(profil\) \{.*?\n    }','    function setzeCodec(profil) { lastCodec = profil; btAktiv = profil; }',s,flags=re.S)
    p.write_text(s)
    p=shell/'Bar/Widgets/Volume.qml' ;s=p.read_text().replace('shown: Audio.ready', 'shown: true').replace('import QtQuick','import QtQuick\nimport Quickshell.Io',1)
    end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target: "audioProbe"
        function cell(): string {
            const p = root.mapToGlobal(root.width / 2, root.height / 2);
            return JSON.stringify({x:p.x,y:p.y});
        }
        function state(): string {
            const popup = Runtime.activePopout;
            const target = popup ? popup.initialFocusTarget() : null;
            let panel = target;
            while (panel && !("audio" in panel)) panel = panel.parent;
            const focus = popup && popup.focusWindow ? popup.focusWindow.activeFocusItem : null;
            const controls = panel ? panel.controls(panel, []).map(c => {
                const p = c.mapToGlobal(c.width / 2, c.height / 2);
                return {name:c.Accessible.name,x:p.x,y:p.y,focused:c.activeFocus};
            }) : [];
            return JSON.stringify({visible:!!popup && popup.visible, keyboard:!!popup && popup.takesKeyboard,
                focus:focus ? focus.Accessible.name : "", width:popup ? popup.width : 0,
                height:popup ? popup.height : 0, controls:controls,
                volume:Audio.volume, muted:Audio.muted, micVolume:Audio.micVolume, micMuted:Audio.micMuted,
                sink:Audio.label(Audio.sink), source:Audio.label(Audio.source),
                streams:Audio.appStreams.map(n=>({name:Audio.label(n),volume:Audio.streamVolume(n),muted:n.audio.muted})),
                lastRoute:Audio.lastRoute,lastCodec:Audio.lastCodec});
        }
        function scenario(mode: string): void { Audio.scenario(mode); }
        function focus(name: string): void {
            const popup = Runtime.activePopout;
            let panel = popup ? popup.initialFocusTarget() : null;
            while (panel && !("audio" in panel)) panel = panel.parent;
            if (!panel) return;
            const control = panel.controls(panel, []).find(c=>c.Accessible.name === name);
            if (control) control.forceActiveFocus(Qt.TabFocusReason);
        }
    }
'''+s[end:];p.write_text(s)


def exercise(run, launch, wait, ipc, processes, shell, args):
    def state(): return json.loads(ipc('audioProbe','state'))
    def pointer(*commands):
        proc=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands)], 'audio-pointer.log')
        processes.remove(proc)
        return proc
    target = Path('/work/audio-focus-target'); target.mkdir()
    (target / 'shell.qml').write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\nShellRoot {\n property var received: []\n FloatingWindow {\n  visible:true; implicitWidth:300; implicitHeight:120; title:"Audio focus test"\n  Item { id:sink; anchors.fill:parent; focus:true\n   Keys.onPressed:event=>{received=received.concat([event.key]); event.accepted=true;}\n  }\n }\n IpcHandler { target:"probe"; function state():string {return JSON.stringify({focused:sink.activeFocus,keys:received});} }\n}\n')
    launch(['/test-bin/qs','-p',str(target)], 'audio-focus-target.log')
    def focus():
        result=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(result.stdout) if result.returncode == 0 else {'focused':False,'keys':[]}
    wait(lambda:focus()['focused'],'underlying audio focus target')
    cell=json.loads(ipc('audioProbe','cell'))
    # One keyboard remains alive across every native key test. Subsequent IPC
    # chooses a control, but all mutations below use real key/pointer events.
    events=[('tap',106),('tap',50),('tap',106),('tap',50),('tap',28),('tap',106),('tap',50),('tap',28),('tap',28),('tap',28),('tap',1)]
    commands=['move',round(cell['x']*args.scale),round(cell['y']*args.scale),'pause',1200,'click',272,'pause',1600]
    for ev in events: commands += list(ev)+['pause',1500]
    commands += ['pause',500,'tap',30,'pause',1500]
    keys=pointer(*commands)
    results={}
    try:
        wait(lambda:state()['keyboard'] and state()['focus']=='Output volume','audio native initial focus')
        initial=state();results['initial']=initial
        assert initial['width'] <= args.width/args.scale and initial['height'] < args.height/args.scale, initial
        time.sleep(0.6)
        run(['grim','/work/audio-basic.png'])
        wait(lambda:state()['volume']==50,'Right adjusts output by 5')
        wait(lambda:state()['muted'],'M mutes output')
        ipc('audioProbe','focus','Microphone volume')
        wait(lambda:state()['micVolume']==70,'Right adjusts microphone by 5')
        wait(lambda:state()['micMuted'],'M mutes microphone')
        ipc('audioProbe','focus','Output: Bluetooth headphones')
        wait(lambda:state()['sink']=='Bluetooth headphones','Enter selects output')
        ipc('audioProbe','focus','Music player volume')
        wait(lambda:state()['streams'][0]['volume']==75,'Right adjusts stream by 5')
        wait(lambda:state()['streams'][0]['muted'],'M mutes stream')
        # Grow the already mapped popup: frozen geometry and scrolling must
        # keep the last extension reachable without changing the native grab.
        ipc('audioProbe','scenario','extras')
        ipc('audioProbe','focus','Route Music player')
        wait(lambda:state()['lastRoute']=='Music player','Enter cycles route')
        ipc('audioProbe','focus','Use AAC Bluetooth codec')
        wait(lambda:state()['lastCodec']=='aac','Enter selects codec')
        run(['grim','/work/audio-extras.png'])
        ipc('audioProbe','focus','Input: USB microphone')
        wait(lambda:state()['source']=='USB microphone','Enter selects input')
        results['exercised']=state()
        # Remove focused devices while the native popup is still open.
        # This exercises focus recovery rather than synthesizing an OSD and
        # remapping a second popup at the exact same time.
        ipc('audioProbe','scenario','empty')
        wait(lambda:state()['keyboard'] and state()['focus'].startswith('Unmute'),'empty audio panel')
        results['empty']=state()
        time.sleep(0.6)
        run(['grim','/work/audio-empty.png'])
        wait(lambda:not state()['visible'],'Escape closes empty audio')
        wait(lambda:focus()['keys']==[65],'Only A returns to underlying window')
        results['returned']=focus()
    finally:
        Path('/work/audio-last-state.json').write_text(json.dumps(state(), indent=2))
        keys.wait(timeout=12)
    log=Path('/work/shell.log').read_text()
    assert not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log),log
    Path('/work/audio-result.json').write_text(json.dumps(results,indent=2))
