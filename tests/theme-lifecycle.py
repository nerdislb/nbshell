"""Theme fan contract in a private compositor; never applies a host theme."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    for i in range(24):
        Path(f'/work/scene-{i}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="640"><rect width="1024" height="640" fill="#{(i*782331+0x345678)%0xffffff:06x}"/><circle cx="700" cy="160" r="65" fill="#efc98a"/><path d="M0 600L220 180L580 640M250 640L700 270L1024 620V640" fill="#273147"/></svg>')
    p = shell / 'Services/ThemeIndex.qml'
    s = p.read_text().replace('    id: root', '    id: root\n    property var testActions: []', 1)
    s = re.sub(r'    function refresh\(\) \{.*?\n    }', '    function refresh() {}', s, flags=re.S)
    s = re.sub(r'    function apply\(name\) \{.*?\n    }', '    function apply(name) { testActions = testActions.concat([name]); }', s, flags=re.S)
    s = s.replace('running: true', 'running: false')
    p.write_text(s)
    p = shell / 'Wallpaper/ThemeGallery.qml'
    s = p.read_text().replace('    id: root', '''    id: root
    property bool probeFocus: keys.activeFocus
    property real probeBottom: frame.y + frame.height
''', 1)
    p.write_text(s)
    p = shell / 'shell.qml'
    s = p.read_text(); end = s.rfind('}')
    # Use the production MotionLoader, not a second independent panel.
    s = s.replace('sourceComponent: Component { ThemeGallery {} }', 'sourceComponent: Component { ThemeGallery { Component.onCompleted: themeProbe.gallery = this } }')
    end = s.rfind('}')
    s = s[:end] + '''
    IpcHandler {
        id: themeProbe
        target: "themeProbe"
        property var gallery: null
        function setup(): void {
            ThemeIndex.list = Array.from({length:24}, (_,i)=>({name:i===0 ? Config.theme : "fixture-theme-"+i,
                background:Theme.bg, foreground:Theme.fg, red:Theme.red, green:Theme.green,
                yellow:Theme.yellow, blue:Theme.blue, cyan:Theme.cyan, magenta:Theme.magenta,
                wallpaper:i < 22 ? "/work/scene-"+i+".svg" : ""}));
            ThemeIndex.testActions=[];
        }
        function state(): string {
            const p=gallery;
            return JSON.stringify({open:Runtime.themePickerOpen,focus:p?.probeFocus||false,
                selected:p?.selectedName||"",query:p?.query||"",count:p?.filteredThemes.length||0,
                fit:p?.fit||0,bottom:p?.probeBottom||0,height:p?.height||0,width:p?.width||0,
                actions:ThemeIndex.testActions,theme:Config.theme});
        }
        function query(value:string):void { if(gallery)gallery.query=value; }
        function prepend():void {ThemeIndex.list=[{name:"new-theme",background:Theme.bg,foreground:Theme.fg}].concat(ThemeIndex.list);}
        function empty():void {ThemeIndex.list=[];}
        function loading(value:bool):void {ThemeIndex.loading=value;}
    }
''' + s[end:]
    p.write_text(s)


def exercise(run, launch, wait, ipc, processes, shell, args):
    results=[]
    def state():return json.loads(ipc('themeProbe','state'))
    def record(name,condition):
        results.append(dict(test=name,passed=bool(condition),detail=state()))
        Path('/work/theme-results.json').write_text(json.dumps(results,indent=2))
        assert condition,(name,state())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    def key(code):pointer('tap',code,'pause',200)
    def open_picker():
        ipc('themes','open');wait(lambda:state()['open'] and state()['focus'],'theme focus')
        time.sleep(.2)
    def shot(name):run(['grim','/work/theme-'+name+'.png'])
    ipc('themeProbe','setup')
    # A real window proves Exclusive layer keys are not leaked to the client.
    target=Path('/work/theme-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Theme focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}} }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}
''')
    launch(['/test-bin/qs','-p',str(target)],'theme-focus-target.log')
    def underlying():
        result=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(result.stdout) if result.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus')
    # Keep a single virtual keyboard alive: hot-unplugging it after each key
    # changes the compositor seat and invalidates a keyboard-focus test.
    commands=['pause',1200]
    steps=[['tap',106],['tap',15],['mod','shift','tap',15,'mod','none'],['tap',107],
           ['tap',105],['tap',102],['tap',44],['tap',28],['tap',1],['tap',14],
           ['mod','control','tap',22,'mod','none'],['tap',28],['tap',1],
           ['tap',106],['tap',28]]
    for step in steps:commands+=step+['pause',1400]
    driver=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands)],'theme-keyboard.log')
    processes.remove(driver)
    open_picker()
    record('opens at current theme',state()['selected']==args.theme and state()['count']==24)
    record('chrome fits output',state()['bottom']<=args.height/args.scale and state()['fit']>0)
    shot('initial')
    wait(lambda:state()['selected']=='fixture-theme-1','Right')
    record('Right browses without applying',not state()['actions'])
    wait(lambda:state()['selected']=='fixture-theme-2','Tab')
    record('Tab browses forward',state()['focus'])
    wait(lambda:state()['selected']=='fixture-theme-1','Shift Tab')
    record('Shift Tab browses backward',state()['focus'])
    wait(lambda:state()['selected']=='fixture-theme-23','End')
    record('End reaches all themes',state()['count']==24)
    ipc('themeProbe','prepend');time.sleep(.15)
    record('refresh preserves selected identity',state()['selected']=='fixture-theme-23')
    wait(lambda:state()['selected']=='fixture-theme-22','Left')
    record('Left browses backward',state()['focus'])
    wait(lambda:state()['selected']=='new-theme','Home')
    record('Home reaches first theme',state()['focus'])
    wait(lambda:state()['query']=='z','native search')
    record('typing filters and retains focus',state()['count']==0 and state()['focus'])
    shot('empty-search');time.sleep(1.6)
    record('Enter on no matches does not apply or close',state()['open'] and not state()['actions'])
    wait(lambda:state()['query']=='','Escape clears')
    record('first Escape clears query',state()['open'])
    ipc('themeProbe','query','fixture theme 23');time.sleep(.15)
    record('human readable names searchable',state()['count']==1 and state()['selected']=='fixture-theme-23')
    shot('search')
    wait(lambda:state()['query']=='fixture theme 2','Backspace')
    record('Backspace edits filter',state()['focus'])
    wait(lambda:state()['query']=='','Ctrl U')
    record('Ctrl U clears filter',state()['open'])
    ipc('themeProbe','loading','true');time.sleep(1.6)
    record('loading blocks apply',state()['open'] and not state()['actions'])
    ipc('themeProbe','loading','false')
    wait(lambda:not state()['open'],'Escape closes')
    wait(lambda:underlying()['focused'],'returned focus')
    record('Escape restores client focus without leaked keys',not underlying()['keys'])
    open_picker()
    wait(lambda:state()['selected']=='fixture-theme-1','Right after reopening')
    wait(lambda:not state()['open'],'Enter applies')
    record('Enter applies exactly once',len(state()['actions'])==1)
    driver.wait(timeout=5)
    open_picker();shot('reopen')
    record('reopens focused at active theme',state()['focus'] and state()['selected']==args.theme)
    # Click the selected center preview: same guarded apply path as keyboard.
    pointer('move',args.width//2,args.height//2-40,'pause',150,'click',272,'pause',200)
    wait(lambda:not state()['open'],'pointer applies')
    record('center click applies exactly once',len(state()['actions'])==2)
    open_picker();before=state()['selected']
    pointer('move',args.width//2,args.height//2,'notch',1,'pause',150)
    record('wheel browses without applying',state()['selected']!=before and len(state()['actions'])==2)
    before=state()['selected']
    pointer('move',args.width//2,args.height//2-40,'press',272,'pause',100,'move',args.width//2+40,args.height//2-40,'pause',100,'move',args.width//2+100,args.height//2-40,'pause',100,'release',272,'pause',200)
    record('drag browses without applying',state()['selected']!=before and len(state()['actions'])==2)
    ipc('themeProbe','empty');time.sleep(.15);shot('empty-store')
    record('empty store is explicit and safe',state()['count']==0 and state()['open'])
    key(28);record('empty store does not apply',len(state()['actions'])==2)
    pointer('move',10,10,'pause',100,'click',272,'pause',200)
    wait(lambda:not state()['open'],'outside click closes')
    record('outside click closes',not state()['open'])
    record('configured theme unchanged by test backend',state()['theme']==args.theme)
    log=Path('/work/shell.log').read_text()
    assert not re.search(r'(ReferenceError|TypeError|Binding loop|Cannot assign|is not a type)',log),log[-5000:]
    print(json.dumps({'themeChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
