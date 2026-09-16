"""Wallpaper picker contract with private files, configuration and compositor."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    for i in range(26):
        Path(f'/work/wall-{i}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="640"><rect width="1024" height="640" fill="#{(i*782331+0x345678)%0xffffff:06x}"/><circle cx="700" cy="160" r="65" fill="#efc98a"/><path d="M0 600L220 180L580 640M250 640L700 270L1024 620V640" fill="#273147"/></svg>')
    # Fault injection lives only in the private test copy. Other writes use
    # the real CAS helper so the test verifies queued and on-disk state.
    p=shell/'Common/Config.qml';text=p.read_text()
    text=re.sub(r'    readonly property string writeScript:.*', '    readonly property string writeScript: "/work/config-write-probe.py"',text)
    p.write_text(text)
    Path('/work/config-write-probe.py').write_text("import os,sys,json,time\nfrom pathlib import Path\nif Path('/work/fail-write').exists():\n time.sleep(.5)\n print(json.dumps(dict(ok=False,error='Fixture disk rejection')))\n sys.exit(1)\nos.execv(sys.executable,[sys.executable,'/work/shell/scripts/config-write.py',*sys.argv[1:]])\n")
    p=shell/'Services/Wallpapers.qml';s=p.read_text()
    s=s.replace('    id: root','    id: root\n    property var testActions: []',1)
    s=re.sub(r'    function refresh\(\) \{.*?\n    }', '    function refresh() { loading = false; }',s,flags=re.S)
    s=s.replace('    function apply(path) {','    function apply(path) {\n        testActions = testActions.concat(["apply:"+path]);')
    s=s.replace('    function reset() {','    function reset() {\n        testActions = testActions.concat(["reset"]);')
    p.write_text(s)
    p=shell/'Wallpaper/WallpaperPicker.qml';s=p.read_text().replace('    id: root','''    id: root
    property bool probeFocus: keys.activeFocus
    property real probeBottom: frame.y + frame.height
    function probeFocusControl(name) {
        if(name==="preview")previewButton.forceActiveFocus();
        else if(name==="scope")scopeButton.forceActiveFocus();
        else if(name==="dynamic")dynamicButton.forceActiveFocus();
        else if(name==="reset")resetButton.forceActiveFocus();
        else keys.forceActiveFocus();
    }
''',1);p.write_text(s)
    p=shell/'shell.qml';s=p.read_text().replace('WallpaperPicker {}','WallpaperPicker { Component.onCompleted: wallpaperProbe.picker=this }')
    end=s.rfind('}');s=s[:end]+'''
    IpcHandler {
        id: wallpaperProbe
        target:"wallpaperPickerProbe"
        property var picker:null
        function setup():void {
            const map={other:"/keep/other.png"};map[Config.theme]="/work/wall-0.svg";
            Config.setValues({wallpaper:true,wallpaperOverride:"/work/wall-0.svg",wallpaperByTheme:map,wallpaperPickerScope:"theme",dynamicWallpaper:{}});
            Wallpapers.list=Array.from({length:26},(_,i)=>({theme:i<20 ? Config.theme : "other",path:"/work/wall-"+i+".svg"}));
            Wallpapers.testActions=[];
        }
        function state():string {
            const p=picker,f=p?.contentItem.Window.window.activeFocusItem;
            const pos=f ? f.mapToItem(null,0,0) : Qt.point(0,0);
            return JSON.stringify({open:Runtime.wallpaperOpen,focus:p?.probeFocus||false,
                selected:p?.selectedPath||"",query:p?.query||"",count:p?.list.length||0,
                bottom:p?.probeBottom||0,height:p?.height||0,scope:p?.scope||"",
                preferences:p?.preferencesOpen||false,preview:DynamicWallpaper.pickerPreview,
                still:DynamicWallpaper.stillPath,videoEligible:DynamicWallpaper.videoEligible,
                actions:Wallpapers.testActions,override:Config.value("wallpaperOverride", ""),
                map:Config.value("wallpaperByTheme",{}),saving:Config.saving,
                applying:p?.applying||false,error:p?.error||"",
                focusedName:f ? (f.accessibleName || f.Accessible.name || "") : "",
                x:pos.x,y:pos.y,fw:f?.width||0,fh:f?.height||0});
        }
        function focus(name:string):void {picker?.probeFocusControl(name);}
        function query(value:string):void {if(picker)picker.query=value;}
        function prepend():void {Wallpapers.list=[{theme:Config.theme,path:"/work/new.svg"}].concat(Wallpapers.list);}
        function empty():void {Wallpapers.list=[];}
        function loading(value:bool):void {Wallpapers.loading=value;}
        function valid(value:bool):void {Config.configValid=value;}
        function scope(value:string):void {picker?.setScope(value);}
        function preview():void {if(picker)picker.livePreview=!picker.livePreview;}
        function dynamic():void {picker?.showPreferences();}
        function reset():void {picker?.apply(true);}
        function apply():void {picker?.apply(false);}
        function select(index:int):void {picker?.select(index);}
        function day():void {Config.set("dynamicWallpaper",{image:"/work/wall-25.svg",videoEnabled:true,video:"/work/test.mp4"});}
    }
''' +s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('wallpaperPickerProbe','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok),detail=state()))
        Path('/work/wallpaper-picker-results.json').write_text(json.dumps(results,indent=2));assert ok,(name,state())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    def open_picker():
        ipc('wallpaper','pick');wait(lambda:state()['open'] and state()['focus'],'picker focused')
    def shot(name):time.sleep(.15);run(['grim','/work/wallpaper-'+name+'.png'])
    ipc('wallpaperPickerProbe','setup');wait(lambda:not state()['saving'],'setup saved')
    target=Path('/work/wallpaper-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Wallpaper focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}} }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}
''')
    launch(['/test-bin/qs','-p',str(target)],'wallpaper-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying window')
    commands=['pause',1200]
    steps=[['tap',106],['tap',15],['mod','shift','tap',15,'mod','none'],['tap',107],
           ['tap',44],['tap',28],['tap',1],['tap',64],['tap',28],['tap',15],['tap',28],
           ['tap',15],['tap',28],['tap',1],['tap',1]]
    for step in steps:commands+=step+['pause',1300]
    commands+=['pause',60000]
    driver=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands)],'wallpaper-keyboard.log')
    try:
        open_picker()
        record('current-theme collection and configured selection',state()['count']==20 and state()['selected']=='/work/wall-0.svg')
        record('footer and options fit output',state()['bottom']<=args.height/args.scale)
        shot('initial')
        wait(lambda:state()['selected']=='/work/wall-1.svg','Right')
        record('browsing leaves both override and per-theme memory untouched',state()['override']=='/work/wall-0.svg' and state()['map'][args.theme]=='/work/wall-0.svg' and not state()['actions'])
        wait(lambda:state()['selected']=='/work/wall-2.svg','Tab')
        record('Tab browses',state()['focus'])
        wait(lambda:state()['selected']=='/work/wall-1.svg','Shift Tab')
        record('Shift Tab browses back',state()['focus'])
        wait(lambda:state()['selected']=='/work/wall-19.svg','End')
        ipc('wallpaperPickerProbe','prepend');time.sleep(.1)
        record('scan refresh retains selected path',state()['selected']=='/work/wall-19.svg')
        wait(lambda:state()['query']=='z','type search')
        record('no-match search remains focused',state()['count']==0 and state()['focus']);shot('no-match')
        time.sleep(1.5);record('Enter on no match does not apply',state()['open'] and not state()['actions'])
        wait(lambda:state()['query']=='','clear search')
        record('Escape clears search first',state()['open'])
        wait(lambda:state()['focusedName']=='Wallpaper collection','F6 options')
        record('options reachable by keyboard',not state()['focus'])
        wait(lambda:state()['scope']=='all','Enter switches collection')
        record('all collections remain reachable',state()['count']==27)
        wait(lambda:state()['focusedName']=='Desktop preview','Tab preview')
        wait(lambda:state()['preview']=='/work/wall-19.svg','preview toggled')
        record('desktop preview is transient',state()['still']==state()['preview'] and state()['override']=='/work/wall-0.svg' and state()['map'][args.theme]=='/work/wall-0.svg')
        shot('preview')
        wait(lambda:state()['focusedName']=='Dynamic wallpaper settings','Tab dynamic')
        wait(lambda:state()['preferences'],'Enter dynamic')
        record('dynamic settings suspend preview',state()['preview']=='' and state()['still']=='/work/wall-0.svg');shot('dynamic')
        wait(lambda:not state()['preferences'],'Escape returns to picker')
        record('dynamic back restores picker focus and preview',state()['focus'] and state()['preview']=='/work/wall-19.svg')
        wait(lambda:not state()['open'],'Escape closes')
        wait(lambda:underlying()['focused'],'underlying returned')
        record('cancel restores background and preserves memory',state()['preview']=='' and state()['override']=='/work/wall-0.svg' and state()['map'][args.theme]=='/work/wall-0.svg')
        record('focus returns without leaked keys',not underlying()['keys'])
        # Keep the virtual keyboard attached for pointer/reopen checks too.
    finally:
        pass  # The outer runner owns and terminates this persistent device.
    open_picker();record('reopen chooses saved path and remembered scope',state()['selected']=='/work/wall-0.svg' and state()['scope']=='all' and state()['preview']=='')
    before=state()['selected'];pointer('move',args.width//2,args.height//2-50,'notch',1,'pause',150)
    record('wheel selects without applying',state()['selected']!=before and not state()['actions'])
    before=state()['selected'];pointer('move',args.width//2,args.height//2-50,'press',272,'pause',100,'move',args.width//2+40,args.height//2-50,'pause',100,'move',args.width//2+100,args.height//2-50,'pause',100,'release',272,'pause',200)
    record('drag selects without applying',state()['selected']!=before and not state()['actions'])
    ipc('wallpaperPickerProbe','select','4');chosen=state()['selected']
    pointer('move',args.width//2,args.height//2-50,'pause',100,'click',272,'pause',150)
    wait(lambda:not state()['open'] and not state()['saving'],'apply saved and closed')
    record('center click applies exactly once and saves both fields',state()['actions']==['apply:'+chosen] and state()['override']==chosen and state()['map'][args.theme]==chosen and state()['map']['other']=='/keep/other.png')
    stored=json.loads(Path('/home/user/.config/nbshell/config.json').read_text())
    record('atomic selection reaches private disk',stored['wallpaperOverride']==chosen and stored['wallpaperByTheme'][args.theme]==chosen)
    open_picker();ipc('wallpaperPickerProbe','valid','false');ipc('wallpaperPickerProbe','apply')
    record('rejected save stays open with an error',state()['open'] and bool(state()['error']) and not state()['applying']);shot('error')
    ipc('wallpaperPickerProbe','valid','true')
    Path('/work/fail-write').touch()
    ipc('wallpaperPickerProbe','select','7');before=len(state()['actions'])
    ipc('wallpaperPickerProbe','apply');ipc('wallpaperPickerProbe','apply')
    record('pending save blocks duplicate activation and stays open',state()['open'] and state()['applying'] and len(state()['actions'])==before+1)
    wait(lambda:not state()['saving'] and not state()['applying'],'failed write completed')
    record('asynchronous failure remains visible and restores saved selection',state()['open'] and 'Fixture disk rejection' in state()['error'] and state()['override']==chosen and state()['map'][args.theme]==chosen)
    shot('write-error');Path('/work/fail-write').unlink()
    ipc('wallpaperPickerProbe','reset')
    wait(lambda:not state()['open'] and not state()['saving'],'reset saved')
    record('theme default clears only current theme memory',state()['override']=='' and args.theme not in state()['map'] and state()['map']['other']=='/keep/other.png')
    open_picker();ipc('wallpaperPickerProbe','day');wait(lambda:not state()['saving'],'dynamic configured')
    ipc('wallpaperPickerProbe','select','5');ipc('wallpaperPickerProbe','preview')
    record('preview overrides dynamic still and suspends video eligibility',state()['still']==state()['selected'] and not state()['videoEligible'])
    ipc('wallpaper','pick');wait(lambda:not state()['open'],'external close')
    record('external close clears transient preview',state()['preview']=='' and state()['still']=='/work/wall-25.svg')
    open_picker();ipc('wallpaperPickerProbe','empty');time.sleep(.15);shot('empty')
    record('empty collection remains usable',state()['open'] and state()['count']==0)
    before=len(state()['actions']);ipc('wallpaperPickerProbe','apply');record('empty collection cannot apply',len(state()['actions'])==before)
    pointer('move',10,10,'pause',100,'click',272,'pause',150);wait(lambda:not state()['open'],'outside closes')
    record('outside click closes without selection side effects',len(state()['actions'])==before)
    log=Path('/work/shell.log').read_text()
    assert not re.search(r'(ReferenceError|TypeError|Binding loop|Cannot assign|is not a type)',log),log[-5000:]
    print(json.dumps({'wallpaperChecks':len(results),'theme':args.theme,'size':[args.width,args.height]}))
