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
        function windows(): string {
            root.open();
            root.activate(root.tree.findIndex(e => e.label === "System"));
            root.activate(root.items.findIndex(e => e.label === "Windows"));
            return JSON.stringify(root.items.map(e => e.label));
        }
        function search(value: string): void { root.setFilter(value); }
        function step(delta: int): void { root.move(delta); }
        function back(): void { root.back(); }
        function lastWindowsItem(): void { root.selected = root.items.length - 1; }
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

    path = shell / 'Launcher/Launcher.qml'
    source = path.read_text().replace('import QtQuick', 'import Quickshell.Io\nimport QtQuick', 1)
    end = source.rfind('}')
    source = source[:end] + """
    IpcHandler {
        target: "launcherProbe"
        function search(value: string): void { input.text = value; }
        function step(delta: int): void { root.move(delta); }
        function lateFiles(): bool {
            input.text = ">";
            root.pointerPosition = {x: 10, y: 20};
            const before = root.results;
            SearchProviders.files = SearchProviders.files.slice();
            return root.results === before && root.pointerPosition !== null;
        }
        function confirm(): bool {
            input.text = ">";
            const i = root.results.findIndex(e => e.confirm);
            if (i < 0) return false;
            root.selected = i; root.accept();
            return root.pending !== null;
        }
        function state(): string {
            const point = box.mapToItem(root.contentItem, 0, 0);
            const row = list.itemAtIndex(root.selected);
            return JSON.stringify({selected:root.selected,count:root.results.length,
                x:point.x,y:point.y,w:box.width,h:box.height,sw:root.width,sh:root.height,
                query:input.text,mode:root.mode,pending:root.pending !== null,focused:input.activeFocus,
                rowVisible:!!row && row.y >= list.contentY-1 && row.y+row.height <= list.contentY+list.height+1});
        }
    }
""" + source[end:]
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

    # Exercise the real Windows submenu in each private theme/geometry run.
    labels = json.loads(ipc('menuProbe', 'windows'))
    assert labels == ['Start Windows', 'Start Windows for builds', 'Install / Configure',
                      'Shared folder', 'Installation console', 'Windows sign-in', 'Status', 'Stop Windows'], labels
    wait(mapped, 'Windows submenu mapped'); time.sleep(.4)
    windows_state = state(); bounds(windows_state)
    run(['grim', '/work/windows-menu.png'])
    ipc('menuProbe', 'lastWindowsItem'); time.sleep(.3)
    last_windows_state = state(); bounds(last_windows_state)
    run(['grim', '/work/windows-menu-last.png'])
    ipc('menu', 'close')
    wait(lambda:not mapped(), 'Windows submenu closes')
    Path('/work/windows-menu-result.json').write_text(json.dumps({'labels': labels, 'state': windows_state}, indent=2))

    # Filtering and drilling keep the header fixed; wrap navigation remains
    # keyboard-owned even when rows move under a stationary pointer.
    ipc('menu', 'open'); wait(mapped, 'menu reopens'); time.sleep(.2)
    initial = state()
    ipc('menuProbe', 'search', 'network'); time.sleep(.25)
    filtered = state(); bounds(filtered)
    assert filtered['y'] == initial['y'], (initial, filtered)
    run(['grim', '/work/menu-search.png'])
    ipc('menuProbe', 'search', 'zzzz-no-matching-menu-entry'); time.sleep(.2)
    empty = state(); assert empty['count'] == 0 and empty['y'] == initial['y'], empty
    run(['grim', '/work/menu-empty.png'])
    ipc('menuProbe', 'search', ''); time.sleep(.2)
    ipc('menuProbe', 'step', '-1'); time.sleep(.25)
    wrapped = state(); bounds(wrapped)
    assert wrapped['selected'] == wrapped['count']-1, wrapped
    ipc('menu', 'close'); wait(lambda:not mapped(), 'menu closes')

    def launcher_state(): return json.loads(ipc('launcherProbe', 'state'))
    def launcher_mapped():
        return any(l['namespace']=='nbshell:launcher' and l['mapped'] for l in json.loads(run(['/test-bin/umbriel','layers','--json']).stdout))
    # Keep a keyboard attached while the real text field owns focus.
    keyboard = launch(['/test-bin/pointer-client',str(args.width),str(args.height),'pause','6000','tap','1','pause','1500','tap','1','pause','1500','tap','1','pause','500','tap','30','pause','3000'], 'launcher-keyboard.log')
    try:
        time.sleep(.2); ipc('launcher', 'open'); wait(launcher_mapped, 'launcher maps'); time.sleep(.4)
        first_launcher = launcher_state(); bounds(first_launcher)
        assert first_launcher['focused'], first_launcher
        run(['grim', '/work/launcher-first.png'])
        for query, mode in [('>','cmd'),('!','app'),('#','window'),('^','clipboard'),('=2+2','calculator'),('@missing-fixture','file')]:
            ipc('launcherProbe','search',query); time.sleep(.2)
            current = launcher_state()
            assert current['mode'] == mode, current
            assert current['y'] == first_launcher['y'], (first_launcher,current)
            if mode == 'calculator':
                bounds(current); run(['grim','/work/launcher-calculator.png'])
        ipc('launcherProbe', 'search', 'zzzz-no-matching-launcher-entry'); time.sleep(.3)
        empty_launcher = launcher_state(); assert empty_launcher['count'] == 0, empty_launcher
        assert empty_launcher['y'] == first_launcher['y'], empty_launcher
        run(['grim','/work/launcher-empty.png'])
        assert ipc('launcherProbe', 'lateFiles') == 'true', 'Late file results changed command selection'
        assert ipc('launcherProbe', 'confirm') == 'true', 'Guarded command must require confirmation'
        time.sleep(.2); run(['grim','/work/launcher-confirm.png'])
        # First Escape cancels confirmation, second clears search, third closes.
        wait(lambda:not launcher_state()['pending'], 'Escape cancels confirmation')
        assert launcher_mapped() and launcher_state()['query'] == '>', launcher_state()
        wait(lambda:launcher_state()['query'] == '', 'Escape clears query')
        assert launcher_mapped()
        wait(lambda:not launcher_mapped(), 'Escape closes launcher')
        wait(lambda:focus()['keys'] == [65,65], 'Launcher returns focus without leaked keys')
        log = Path('/work/shell.log').read_text()
        assert not any(word in log for word in ['Binding loop','ReferenceError','TypeError','Unable to assign']), log
        Path('/work/round1-result.json').write_text(json.dumps({'menuInitial':initial,'filtered':filtered,'wrapped':wrapped,'launcher':first_launcher,'emptyLauncher':empty_launcher,'prefixes':True,'confirmation':True},indent=2))
    finally:
        if keyboard.poll() is None: keyboard.terminate()
        keyboard.wait(timeout=3)
        processes.remove(keyboard)
