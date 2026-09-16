"""Real private Wayland presentation checks for the remaining native surfaces.

All services run in the existing lifecycle sandbox: no host HOME, network,
system D-Bus, real accounts or writable source. Never invoke external actions.
"""
import json
import re
import time
import shutil
import subprocess
from pathlib import Path

SURFACES = {
    'qr': ('Net/QrWindow.qml', 'qrOpen', 'box'),
    'procs': ('Procs/ProcessList.qml', 'procsOpen', 'box'),
    'todo': ('Todo/TodoList.qml', 'todoOpen', 'box'),
    'notes': ('Notes/NotesWindow.qml', 'notesOpen', 'root.contentItem'),
    'shopping': ('Shopping/ShoppingListWindow.qml', 'shoppingListOpen', 'box'),
    'habits': ('Habits/HabitsList.qml', 'habitsOpen', 'box'),
    'dashboard': ('Menu/Dashboard.qml', 'dashboardOpen', 'box'),
    'hub': ('Menu/SystemHub.qml', 'hubOpen', 'box'),
    'agents': ('Menu/AgentCenter.qml', 'agentCenterOpen', 'box'),
    'audio': ('Music/AudioTools.qml', 'audioToolsOpen', 'box'),
    'store': ('Store/StoreWindow.qml', 'storeOpen', 'frame'),
}


def instrument(shell):
    # Populate only the disposable HOME. Long names and each habit mode matter.
    stateDir=Path('/home/user/.local/state/nbshell');stateDir.mkdir(parents=True,exist_ok=True)
    now=int(time.time()*1000)
    (stateDir/'todo.json').write_text(json.dumps([{'id':str(i),'text':'Task '+str(i)+' <literal> '+'long '*12,'done':False,'created':now,'updated':now} for i in range(24)]))
    (stateDir/'notes.json').write_text(json.dumps([{'id':str(i),'text':'Note '+str(i)+'\nFixture body','title':'Note '+str(i),'created':now,'updated':now} for i in range(16)]))
    habitsDir=Path('/home/user/Sync/nbshell');habitsDir.mkdir(parents=True,exist_ok=True)
    (habitsDir/'habits.json').write_text(json.dumps({'version':'1.0.0','habits':[{'id':str(i),'name':mode+' <literal> '+'long '*7,'mode':mode,'routine':'general','targetValue':30,'unit':'times','shields':2,'created':now,'updated':now} for i,mode in enumerate(['COUNTER','DURATION','TIMER','NUMBER','CHECKBOX'])],'entries':[]}))
    for name, (file, flag, item) in SURFACES.items():
        p = shell / file
        s = p.read_text()
        if 'import Quickshell.Io' not in s:
            s = 'import Quickshell.Io\n' + s
        if name == 'qr' and 'id: box' not in s:
            s = s.replace('    PanelSurface {', '    PanelSurface {\n        id: box', 1)
        end = s.rfind('}')
        probe = '''
    IpcHandler {
        target: "paritySurface"
        function state(): string {
            const item = ITEM;
            const pos = item.mapToItem(root.contentItem, 0, 0);
            const f = root.contentItem.Window.window.activeFocusItem;
            return JSON.stringify({name: "NAME", x: pos.x, y: pos.y, w: item.width, h: item.height,
                windowWidth: root.width, windowHeight: root.height, focus: f !== null,
                accessible: f?.accessibleName || "", reduced: Theme.reducedMotion});
        }
        function page(value: int): void { PAGE }
    }
'''.replace('ITEM', item).replace('NAME', name).replace('PAGE', 'root.page=value;' if name in ['dashboard','agents'] else '')
        s = s[:end] + probe + s[end:]
        extras={
            'qr': 'function detail():string{return JSON.stringify({ok:root.qr?.ok,size:root.size,module:root.modul});}',
            'todo': 'function detail():string{return JSON.stringify({count:Todo.count,done:Todo.doneCount});} function inputText(value:string):void{input.text=value;input.forceActiveFocus();}',
            'notes': 'function detail():string{return JSON.stringify({dirty:root.dirty,confirm:root.confirmDiscard,count:Notes.list.length});} function inputText(value:string):void{editor.text=value;editor.forceActiveFocus();}',
            'habits': 'function detail():string{return JSON.stringify({count:Habits.count,done:Habits.doneCount,entries:Habits.entriesRaw,pending:root.pendingDelete});} function inputText(value:string):void{input.text=value;input.forceActiveFocus();}',
            'procs': 'function detail():string{return JSON.stringify({pending:root.pendingSignal,pid:root.selectedPid});} function selectPid(pid:int):void{ const entry=Procs.shown.find(p=>p.pid===pid); if(entry)root.selectProcess(pid,entry.started);filterInput.forceActiveFocus(); }',
        }.get(name,'')
        s=s.replace('target: "paritySurface"', extras+'\n        target: "paritySurface"')
        p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    flags=[v[1] for v in SURFACES.values()]
    s=s[:end]+'''
    IpcHandler {
        target: "parityFixture"
        function open(name: string): void { Runtime[name] = true; }
        function close(): void { '''+';'.join('Runtime.'+flag+'=false' for flag in flags)+'''; }
        function state(name: string): bool { return Runtime[name]; }
    }
'''+s[end:];p.write_text(s)
    for name in ['calendar', 'ytmusic', 'pit-wall', 'omamail', 'wetter', 'headset', 'buds-control', 'hermarchy-agent']:
        shutil.copytree('/source/plugins/'+name, Path('/home/user/.config/nbshell/plugins')/name,
                        ignore=shutil.ignore_patterns('target', '.git', 'node_modules'))
    p=shell/'shell.qml';s=p.read_text();s='import QtQml.Models\nimport Quickshell.Wayland\nimport qs.Touchpad as Input\nimport qs.Wallpaper as WallpaperUi\n'+s;end=s.rfind('}')
    s=s[:end]+"""
    property string parityExtra: ""
    Instantiator {
        id: pluginHosts
        model: ["calendar","ytmusic","pit-wall","omamail"]
        delegate: Item {
            id: host
            required property string modelData
            property bool created: false
            readonly property bool chosen: shell.parityExtra === modelData
            readonly property bool ready: panel.status === Loader.Ready
            readonly property bool opened: panel.item?.opened || false
            function openPanel() {
                if (!chosen) return;
                if (panel.item) { panel.item.open("{}"); return; }
                if (modelData !== "calendar" && serviceLoader.status !== Loader.Ready) return;
                panel.setSource("file:///home/user/.config/nbshell/plugins/" + modelData + (modelData === "omamail" ? "/ui/App.qml" : "/Panel.qml"),modelData === "calendar" ? {} : {service:serviceLoader.item});
            }
            function closePanel() { if (panel.item) panel.item.close(); }
            onChosenChanged: if (chosen) { created=true; Qt.callLater(openPanel); } else closePanel()
            Loader {
                id: serviceLoader
                active: host.created && host.modelData !== "calendar"
                source: !active ? "" : "file:///home/user/.config/nbshell/plugins/" + host.modelData + (host.modelData === "omamail" ? "/ui/Service.qml" : "/Service.qml")
                onLoaded: host.openPanel()
            }
            Loader { id: panel; onLoaded: if (host.chosen) item.open("{}") }
        }
    }
    PanelWindow {
        id: extraWindow
        visible: ["touchpad","phone","nearby","updates","wetter","headset","buds-control","hermarchy-agent","kdeconnect","wallpaper"].includes(shell.parityExtra)
        anchors { left:true;right:true;top:true;bottom:true }
        color: Theme.bg
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        FocusScope {
            id: extraKeys
            anchors.fill: parent; focus: true
            Keys.onEscapePressed: shell.parityExtra=""
            onVisibleChanged: if (visible) forceActiveFocus()
            Flickable {
                anchors.fill: parent; anchors.margins: Theme.panelPadding
                contentHeight: extras.implicitHeight; clip:true
                Column {
                    id: extras; width: parent.width; spacing: Theme.spaceMd
                    Loader { visible: active; active: shell.parityExtra === "touchpad"; width:parent.width; height: active ? extraWindow.height - Theme.panelPadding*2 : 0; sourceComponent: Component { Input.TouchpadPanel { onCloseRequested: shell.parityExtra="" } } }
                    Loader { visible: active; active: shell.parityExtra === "phone"; width:parent.width; sourceComponent: Component { PhonePanel { rowWidth:parent.width; active:false } } }
                    Loader { visible: active; active: shell.parityExtra === "nearby"; width:parent.width; sourceComponent: Component { NearbyPanel { rowWidth:parent.width; active:false } } }
                    Loader {
                        id: widgetFixture
                        visible: false
                        active: ["wetter","headset","buds-control","hermarchy-agent","kdeconnect"].includes(shell.parityExtra)
                        source: !active ? "" : shell.parityExtra === "kdeconnect" ? "Bar/Widgets/KdeConnect.qml" : "file:///home/user/.config/nbshell/plugins/" + shell.parityExtra + "/BarWidget.qml"
                        onLoaded: {
                            if (shell.parityExtra === "wetter") item.data={ok:true,ort:"Long fixture location",temp:18,gefuehlt:17,wind:8,feuchte:42,tage:[]};
                            if (shell.parityExtra === "headset") item.data={ok:true,geraet:"Long fixture headset name",level:73,charging:true};
                            widgetContent.sourceComponent=item.popout;
                        }
                    }
                    Loader { id: widgetContent; visible: active; width:parent.width; active:widgetFixture.active; onLoaded: { item.closePopout=()=>shell.parityExtra=""; } }
                    Loader { visible: active; active: shell.parityExtra === "wallpaper"; width:parent.width; height:active ? extraWindow.height-Theme.panelPadding*2 : 0; sourceComponent: Component { WallpaperUi.WallpaperSettings { onBack: shell.parityExtra="" } } }
                    Loader { id: updateFixture; visible: active; active: shell.parityExtra === "updates"; width:parent.width; sourceComponent: Component { UpdatePanel { rowWidth:parent.width; showClose:true; closePanel:()=>shell.parityExtra="" } } }
                }
            }
        }
    }
    IpcHandler {
        target:"parityExtra"
        function open(name:string):void { shell.parityExtra=name; Qt.callLater(()=>extraKeys.forceActiveFocus()); }
        function close():void { shell.parityExtra=""; }
        function state():string { const index=["calendar","ytmusic","pit-wall","omamail"].indexOf(shell.parityExtra); const host=index<0?null:pluginHosts.objectAt(index); return JSON.stringify({name:shell.parityExtra,visible:extraWindow.visible,loaded:host?.ready||false,opened:host?.opened||false}); }
        function fork():void { updateFixture.item.tab="fork"; }
        function desktop(on:bool):void { Config.set("workDesktop",on); }
        function populateWidget():void {
            if (shell.parityExtra === "wetter") widgetFixture.item.data={ok:true,ort:"Long fixture location <literal>",temp:18,gefuehlt:17,wind:8,feuchte:42,tage:[{datum:"2026-09-16",code:3,max:20,min:12,regen:30}],auf:"2026-09-16T06:30:00",unter:"2026-09-16T19:30:00",stand:"2026-09-16T12:00:00"};
            if (shell.parityExtra === "headset") widgetFixture.item.data={ok:true,geraet:"Long fixture headset name <literal>",level:73,charging:true};
        }
        function devices():void { Phone.available=true;Phone.scrcpyAvailable=true;Phone.connected=true;Phone.webcamReady=true;Phone.model="Fixture phone";Nearby.devices=[{alias:"Fixture device with a very long public name",model:"Synthetic phone",ip:"192.0.2.1"}]; }
    }
"""+s[end:];s='import qs.Bar.Widgets\n'+s;p.write_text(s)
    # Synthetic public QR; never read a real connection or password.
    script=shell/'scripts/wifi-qr.sh'
    matrix=subprocess.check_output(['qrencode','-t','ASCII','-m','4','WIFI:T:nopass;S:Fixture-network;;'],text=True)
    rows=[line[::2] for line in matrix.splitlines()]
    payload=json.dumps({'ok':True,'ssid':'Fixture-network','size':len(rows),'rows':rows,'note':'Synthetic QR fixture'})
    script.write_text("#!/bin/sh\ncat <<'FIXTURE'\n"+payload+"\nFIXTURE\n")



def exercise(run, launch, wait, ipc, processes, shell, args):
    results=[]
    def record(name, ok):
        results.append({'test':name,'passed':bool(ok)})
        Path('/work/parity-results.json').write_text(json.dumps(results,indent=2))
        if not args.parity_snapshot: assert ok,name
    def pointer(*cmd):
        run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','180000'],'parity-seat.log')
    def state():return json.loads(ipc('paritySurface','state'))
    def shot(name):run(['grim','/work/parity-'+name+'.png'])
    states={}
    for name,(_,flag,_) in ([] if args.parity_extras_only else SURFACES.items()):
        ipc('parityFixture','open',flag)
        wait(lambda: state()['name']==name,name+' loaded')
        time.sleep(.45)
        s=state();states[name]=s
        record(name+' frame fits output',s['x']>=-1 and s['y']>=-1 and s['x']+s['w']<=s['windowWidth']+1 and s['y']+s['h']<=s['windowHeight']+1)
        record(name+' gets keyboard focus',s['focus'])
        shot(name)
        def detail():return json.loads(ipc('paritySurface','detail'))
        if name=='qr':
            record('QR uses integer-sized modules and a real matrix',detail()['ok'] and detail()['module']>=1 and detail()['size']>=29)
            pointer('tap',15,'pause',50);shot('qr-focus')
            decoded=run(['zbarimg','--quiet','--raw','/work/parity-qr.png'],False)
            record('Rendered QR decodes to synthetic Wi-Fi payload',decoded.returncode==0 and decoded.stdout.strip()=='WIFI:T:nopass;S:Fixture-network;;')
        if name=='procs':
            victim=launch(['/usr/bin/sleep','90'],'parity-victim.log')
            # Its intentional exit must not trip the compositor/server watchdog.
            processes.remove(victim)
            time.sleep(2.2);ipc('paritySurface','selectPid',str(victim.pid))
            record('process fixture selected by PID',detail()['pid']==victim.pid)
            pointer('mod','ctrl','key-press',37,'pause',900,'key-release',37,'mod','none','pause',100)
            record('held Ctrl-K only arms confirmation',victim.poll() is None and bool(detail()['pending']))
            pointer('mod','ctrl','tap',37,'mod','none','pause',200)
            wait(lambda:victim.poll() is not None,'confirmed private process stops')
            record('second Ctrl-K stops only the selected private process',victim.poll() is not None)
        if name=='todo':
            before=detail()['count'];ipc('paritySurface','inputText','Native task fixture');pointer('tap',28,'pause',150)
            record('Enter adds a native task',detail()['count']==before+1)
            pointer('tap',15,'pause',100);record('Tab toggles native task',detail()['done']>=1)
        if name=='notes':
            ipc('paritySurface','inputText','Unsaved fixture');pointer('tap',1,'pause',100)
            record('Escape guards unsaved notes',detail()['dirty'] and detail()['confirm'] and ipc('parityFixture','state',flag)=='true')
        if name=='habits':
            before=detail()['count'];ipc('paritySurface','inputText','Native habit // general');pointer('tap',28,'pause',150)
            record('Enter adds a native habit',detail()['count']==before+1)
            pointer('tap',15,'pause',100);record('Tab toggles native habit',detail()['done']>=1)
        if name in ['dashboard','agents']:
            for page in range(1,4 if name=='dashboard' else 3):
                ipc('paritySurface','page',str(page));time.sleep(.25);shot(name+'-'+str(page))
        pointer('tap',1,'pause',200)
        record(name+' Escape closes',ipc('parityFixture','state',flag)=='false')
        ipc('parityFixture','close');time.sleep(.25)
    for name in ([] if args.parity_core_only else ['touchpad','phone','nearby','updates','calendar','ytmusic','pit-wall','omamail','wetter','headset','buds-control','hermarchy-agent','kdeconnect','wallpaper']):
        ipc('parityExtra','open',name)
        if name in ['phone','nearby']:
            ipc('parityExtra','devices')
        if name in ['calendar','ytmusic','pit-wall','omamail']:
            wait(lambda:json.loads(ipc('parityExtra','state'))['loaded'],name+' plugin loaded')
        time.sleep(.5)
        if name in ['wetter','headset']:
            ipc('parityExtra','populateWidget');time.sleep(.1)
        shot(name)
        extra=json.loads(ipc('parityExtra','state'))
        record(name+' integration opens',extra['loaded'] and extra['opened'] if name in ['calendar','ytmusic','pit-wall','omamail'] else extra['visible'])
        if name=='updates':
            ipc('parityExtra','fork');time.sleep(.3);shot('updates-fork')
        pointer('tap',1,'pause',100)
        if name=='ytmusic':
            record('music preserves first-Escape close guard',json.loads(ipc('parityExtra','state'))['opened'])
            pointer('tap',1,'pause',100)
        extra=json.loads(ipc('parityExtra','state'))
        record(name+' Escape closes',not extra['opened'] if name in ['calendar','ytmusic','pit-wall','omamail'] else extra['name']=='')
        ipc('parityExtra','close');time.sleep(.25)
    if not args.parity_core_only:
        ipc('parityExtra','desktop','true');time.sleep(.6);shot('workdesktop')
        ipc('parityExtra','desktop','false');time.sleep(.2)
    Path('/work/parity-states.json').write_text(json.dumps(states,indent=2))
    log=Path('/work/shell.log').read_text()
    record('no QML type errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
