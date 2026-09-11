"""Native menu bounds and keyboard regression, private Wayland session only."""
import json
from pathlib import Path
import time


def instrument(shell):
    path = shell / 'Menu/Menu.qml'
    source = path.read_text().replace('import QtQuick', 'import Quickshell.Io\nimport QtQuick', 1)
    end = source.rfind('}')
    source = source[:end] + '''
    IpcHandler {
        target: "menuProbe"
        function state(): string {
            const row = menuRows.itemAt(root.selected);
            const point = box.mapToItem(root.contentItem, 0, 0);
            return JSON.stringify({selected:root.selected, count:root.items.length,
                x:point.x, y:point.y, w:box.width, h:box.height,
                sw:root.width, sh:root.height, scroll:menuScroll.contentY,
                rowVisible:!!row && row.y >= menuScroll.contentY - 1
                    && row.y + row.height <= menuScroll.contentY + menuScroll.height + 1});
        }
    }
''' + source[end:]
    path.write_text(source)


def exercise(run, launch, wait, ipc, processes, shell, args):
    target = Path('/work/menu-focus-target'); target.mkdir()
    (target / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {
  visible:true; implicitWidth:300; implicitHeight:120; title:"Menu focus test"
  Item { id:sink; anchors.fill:parent; focus:true
   Keys.onPressed:event=>{ received=received.concat([event.key]); event.accepted=true; }
  }
 }
 IpcHandler { target:"probe"; function state():string { return JSON.stringify({focused:sink.activeFocus,keys:received}); } }
}
''')
    launch(['/test-bin/qs','-p',str(target)], 'menu-focus.log')
    def focus():
        result = run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(result.stdout) if result.returncode == 0 else {'focused':False,'keys':[]}
    def state(): return json.loads(ipc('menuProbe','state'))
    def mapped():
        return any(l['namespace']=='nbshell:menu' and l['mapped'] for l in json.loads(run(['/test-bin/umbriel','layers','--json']).stdout))
    def bounds(s):
        assert s['x'] >= 0 and s['y'] >= 0 and s['x']+s['w'] <= s['sw']+1 and s['y']+s['h'] <= s['sh']+1, s
        assert s['rowVisible'], s
    wait(lambda:focus()['focused'], 'target focus')
    # Keep the only headless keyboard alive until focus has been inspected.
    keyboard = launch(['/test-bin/pointer-client',str(args.width),str(args.height),
        'pause','1500','tap','15','pause','600'] + ['tap','108','pause','100']*7 +
        ['pause','2000','tap','1','pause','500','tap','30','pause','4000'], 'menu-keyboard.log')
    processes.remove(keyboard)
    try:
        time.sleep(.2); ipc('menu','open')
        wait(mapped, 'menu mapped'); time.sleep(.5)
        first=state(); bounds(first)
        run(['grim','/work/menu-first.png'])
        wait(lambda:state()['selected']==7, 'Down reaches last root item')
        time.sleep(.2)
        last=state(); bounds(last)
        run(['grim','/work/menu-last.png'])
        wait(lambda:not mapped(), 'Escape closes menu')
        wait(lambda:focus()['keys']==[65], 'A returns to target without leaked keys')
        result=focus(); assert result['focused'],result
        Path('/work/menu-result.json').write_text(json.dumps({'first':first,'last':last,'focus':result},indent=2))
    finally:
        keyboard.wait(timeout=10)
