"""Native passive-preview -> network-panel keyboard regression.

Runs only through the private Wayland lifecycle harness, without a system bus.
"""
import json
from pathlib import Path
import time


def instrument(shell):
    path = shell / 'shell.qml'
    source = path.read_text(); end = source.rfind('}')
    source = source[:end] + '''
    IpcHandler {
        target: "controlFocusProbe"
        function state(): string {
            const popup = Runtime.activePopout;
            const target = popup ? popup.initialFocusTarget() : null;
            const focus = popup && popup.focusWindow ? popup.focusWindow.activeFocusItem : null;
            return JSON.stringify({count:Runtime.popoutCount, open:Runtime.controlOpen,
                visible:!!popup && popup.visible, keyboard:!!popup && popup.takesKeyboard,
                initialFocused:!!target && target.activeFocus,
                height:popup ? popup.height : 0,
                focusName:focus ? focus.Accessible.name : ""});
        }
    }
''' + source[end:]
    path.write_text(source)


def exercise(run, launch, wait, ipc, processes, shell, args):
    target = Path('/work/control-focus-target'); target.mkdir()
    (target / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {
  visible:true; implicitWidth:300; implicitHeight:120; title:"Control focus test"
  Item { id:sink; anchors.fill:parent; focus:true
   Keys.onPressed:event=>{received=received.concat([event.key]); event.accepted=true;}
  }
 }
 IpcHandler { target:"probe"; function state():string {return JSON.stringify({focused:sink.activeFocus,keys:received});} }
}
''')
    launch(['/test-bin/qs','-p',str(target)], 'control-focus-target.log')
    def focus():
        result = run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(result.stdout) if result.returncode == 0 else {'focused':False,'keys':[]}
    def state(): return json.loads(ipc('controlFocusProbe','state'))
    wait(lambda:focus()['focused'], 'target focus')
    # Keyboard exists before the preview/click and remains alive during checks.
    commands = []
    for _ in range(2):
        commands += ['move',str(round(args.width-15*args.scale)),str(round(13*args.scale)),
            'pause','1200','click','272','pause','800',
            'move',str(round(args.width-100*args.scale)),str(round(180*args.scale)),
            'pause','400','tap','15','pause','800','tap','1','pause','400','tap','30','pause','1800']
    keyboard = launch(['/test-bin/pointer-client',str(args.width),str(args.height),*commands,'pause','4000'], 'control-keyboard.log')
    processes.remove(keyboard)
    results = []
    try:
        for cycle in range(2):
            wait(lambda:state()['visible'] and not state()['keyboard'], 'passive preview')
            assert focus()['focused'], 'Preview stole keyboard focus'
            wait(lambda:state()['open'] and state()['keyboard'], 'interactive panel')
            wait(lambda:state()['initialFocused'], 'initial control focus')
            initial = state(); assert initial['count'] == 1, initial
            assert initial['height'] < args.height / args.scale - 27, initial
            time.sleep(1.3)
            tab = state(); assert tab['open'] and tab['focusName'], tab
            run(['grim',f'/work/control-tab-{cycle}.png'])
            wait(lambda:state()['count'] == 0 and not state()['open'], 'Escape dismisses panel')
            wait(lambda:focus()['keys'] == [65]*(cycle+1), 'Only A returns to target')
            final = focus(); assert final['focused'], final
            results.append({'initial':initial,'tab':tab,'returned':final})
        Path('/work/control-focus-result.json').write_text(json.dumps(results,indent=2))
    finally:
        keyboard.wait(timeout=15)
