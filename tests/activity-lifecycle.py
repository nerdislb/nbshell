"""Activity UI contract in a private Wayland session; never host clipboard data."""
import json
import re
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Services/Clipboard.qml';s=p.read_text().replace('Config.value("clipboard", true)','false')
    s=s.replace('    id: root','    id: root\n    property var testActions: []',1)
    bodies={
        'persist':'',
        'copy':'testActions = testActions.concat(["copy:"+text]);',
        'copyImage':'testActions = testActions.concat(["copyImage:"+entry.file]);',
        'clear':'testActions = testActions.concat(["clear"]); entries=[]; images=[];',
        'imagePath':'return "file:///usr/share/icons/AdwaitaLegacy/48x48/legacy/dialog-information.png";',
    }
    for name,body in bodies.items():
        s=re.sub(r'(    function '+name+r'\([^)]*\) \{).*?\n    }',r'\1\n        '+body+'\n    }',s,flags=re.S)
    s=s.replace('        imageRemove.command =', '        testActions = testActions.concat(["removeImage:"+entry.file]);\n        imageRemove.command =')
    s=s.replace('Qt.resolvedUrl("../scripts/clipboard-images.py").toString().replace("file://", "")','"/work/activity-images.py"')
    Path('/work/activity-images.py').write_text('import json,sys,time\ntime.sleep(.7)\nprint(json.dumps([dict(file="image-"+str(i)+".png") for i in range(12) if "image-"+str(i)+".png"!=sys.argv[3]]))\n')
    p.write_text(s)
    p=shell/'Services/Notify.qml';s=p.read_text()
    s=re.sub(r'(    function focus\(entry\) \{).*?\n    }',r'\1\n        Clipboard.testActions=Clipboard.testActions.concat(["focus:"+entry.key]); return true;\n    }',s,flags=re.S)
    s=s.replace('import qs.Common','import qs.Common\nimport qs.Services',1);p.write_text(s)
    p=shell/'Bar/Widgets/ActivityPanel.qml';s=p.read_text().replace('    id: panel','''    id: panel
    property var testList: list
    property var testPreview: preview
    property var testFooter: footer
    function testFocus(name) {
        if(name==="search")search.forceActiveFocus();
        else if(name==="list")list.forceActiveFocus();
        else if(name==="clear")clearButton.forceActiveFocus();
        else if(name==="dnd")dnd.forceActiveFocus();
        else if(name==="preview")preview.forceActiveFocus();
        else if(name==="copy")copyButton.forceActiveFocus();
        else if(name==="remove")removeButton.forceActiveFocus();
        else if(name==="row")list.itemAtIndex(selectedIndex)?.forceActiveFocus();
    }
''',1);p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"activityProbe"
        function panel():var {
            let p=Runtime.activePopout?.initialFocusTarget();
            while(p && !("selectedKey" in p))p=p.parent;
            return p;
        }
        function setup():void {
            Clipboard.entries=Array.from({length:45},(_,i)=>i===0 ? "A literal <b>clipboard</b> preview\\n"+"Long text, fully scrollable. ".repeat(150) : "Clipboard item "+i);
            Clipboard.images=Array.from({length:12},(_,i)=>({file:"image-"+i+".png"}));
            Notify.history=Array.from({length:18},(_,i)=>({key:"fixture-"+i,appName:"Fixture app",summary:i===0 ? "A literal <b>title</b>" : "Notification "+i,body:"Full notification text. ".repeat(i===0 ? 120 : 2),time:new Date(Date.now()-i*86400000),count:i===0 ? 3 : 1,urgency:1}));
            Notify.popups=[];
            Clipboard.testActions=[];
            Runtime.activityTab="clipboard";
        }
        function state():string {
            const p=panel(),f=Runtime.activePopout?.focusWindow?.activeFocusItem;
            const pos=f ? f.mapToItem(null,0,0) : Qt.point(0,0);
            return JSON.stringify({visible:!!Runtime.activePopout?.visible,
                focus:p?.testList.activeFocus ? "Clipboard history" : (f ? (f.accessibleName || f.Accessible.name) : ""),x:pos.x,y:pos.y,fw:f?.width || 0,fh:f?.height || 0,
                width:Runtime.activePopout?.width || 0,height:Runtime.activePopout?.height || 0,
                tab:Runtime.activityTab,notifyOpen:Runtime.notifyOpen,clipOpen:Runtime.clipOpen,
                rows:p?.rows.length || 0,selected:p?.selectedKey || "",query:p?.query || "",clearArmed:p?.clearArmed || false,
                count:Notify.count,clips:Clipboard.entries.length,images:Clipboard.images.length,dnd:Notify.dnd,
                footerBottom:p ? p.testFooter.mapToItem(null,0,p.testFooter.height).y : 0,
                listY:p?.testList.contentY || 0,previewY:p?.testPreview.contentY || 0,
                removingImage:Clipboard.removingImage,actions:Clipboard.testActions});
        }
        function focus(name:string):void {panel()?.testFocus(name);}
        function tab(name:string):void {panel()?.tabRequested(name);}
        function select(key:string):void {if(panel())panel().selectedKey=key;}
        function query(value:string):void {if(panel())panel().query=value;}
        function prepend():void {Clipboard.entries=["New concurrent item"].concat(Clipboard.entries);}
        function removeImage(file:string):bool {return Clipboard.removeImage({file:file});}
        function empty():void {Clipboard.entries=[];Clipboard.images=[];Notify.clear();}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('activityProbe','state'))
    def record(name,condition,detail=None):
        results.append(dict(test=name,passed=bool(condition),detail=detail))
        Path('/work/activity-results.json').write_text(json.dumps(results,indent=2))
        assert condition,(name,detail or state())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    def open_panel():
        pointer('move',round(args.width-30*args.scale),round(13*args.scale),'pause',1200,'click',272,'pause',1200)
        wait(lambda:state()['visible'],'activity popup ready')
    def click_control(name,button=272):
        ipc('activityProbe','focus',name);time.sleep(.12);s=state()
        x=round((args.width/args.scale-s['width']+s['x']+s['fw']/2)*args.scale)
        y=round((31+s['y']+s['fh']/2)*args.scale)
        pointer('move',x,y,'pause',100,'click',button,'pause',200)
    def shot(name):
        time.sleep(.4);run(['grim','/work/activity-'+name+'.png'])
    ipc('activityProbe','setup')
    target=Path('/work/activity-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 property var received: []
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Activity focus test"
  Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}
 }
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}
''')
    launch(['/test-bin/qs','-p',str(target)],'activity-focus-target.log')
    def underlying():
        res=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(res.stdout) if res.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying window')
    cmd=['move',round(args.width-30*args.scale),round(13*args.scale),'pause',1200,'click',272,'pause',2200]
    for key,delay in [(108,1000),(107,1200),(111,1200),(44,1200),(1,1200),(109,1200),(28,1200),(1,1200),(28,1200),(1,1000),(30,500)]:cmd+=['tap',key,'pause',delay]
    keys=launch(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)],'activity-keyboard.log');processes.remove(keys)
    try:
        wait(lambda:state()['visible'],'opened clipboard')
        wait(lambda:state()['rows']==57,'all stored rows reachable')
        s=state();record('all text and image items rendered without 8/30 cap',s['rows']==57,s)
        record('search initially focused',s['focus']=='Search clipboard',s)
        record('popup fits output',s['width']<=args.width/args.scale and s['height']<=args.height/args.scale-25,s)
        record('footer is visible without outer scrolling',s['footerBottom']<=s['height']-10,s)
        shot('clipboard')
        wait(lambda:state()['focus']=='Clipboard history','Down enters history')
        wait(lambda:state()['selected']=='text:Clipboard item 44','End reaches last stored entry')
        record('last row scrolls into view',state()['listY']>0,state());shot('last-row')
        wait(lambda:state()['clips']==44,'Delete removes selected item')
        record('delete never copies',state()['actions']==[],state())
        ipc('activityProbe','focus','search')
        wait(lambda:state()['query']=='z' and state()['rows']==0,'native typing filters clipboard')
        record('typing in editor filters without list shortcuts',state()['rows']==0,state())
        wait(lambda:state()['query']=='','Escape clears query first')
        record('first Escape leaves popup open',state()['visible'],state())
        ipc('activityProbe','query','literal');time.sleep(.15);ipc('activityProbe','focus','preview')
        wait(lambda:state()['previewY']>0,'PageDown scrolls full preview')
        record('long preview is keyboard scrollable',state()['previewY']>0,state());shot('long-preview')
        ipc('activityProbe','focus','clear')
        wait(lambda:state()['clearArmed'],'Enter arms clear')
        record('first clear does not mutate data',state()['clips']==44 and state()['images']==12,state())
        wait(lambda:not state()['clearArmed'],'Escape cancels clear')
        record('cancel preserves full history',state()['clips']==44 and state()['images']==12,state())
        wait(lambda:state()['clearArmed'],'clear can be armed again')
        ipc('activityProbe','tab','notifications')
        record('switching tabs cancels confirmation',not state()['clearArmed'],state())
        wait(lambda:not state()['visible'],'Escape dismisses popup')
        wait(lambda:underlying()['keys']==[65],'keyboard focus returns to application')
        record('only subsequent A reaches application',underlying()['keys']==[65],underlying())
        keys.wait(timeout=5)
        open_panel()
        ipc('activityProbe','tab','clipboard');time.sleep(.2)
        s=state();geometry=(s['width'],s['height'])
        ipc('activityProbe','tab','notifications');time.sleep(.3)
        s=state();record('IPC flags and geometry survive tab switch',s['notifyOpen'] and not s['clipOpen'] and geometry==(s['width'],s['height']),s)
        shot('notifications')
        ipc('activityProbe','query','no-such-fixture');wait(lambda:state()['rows']==0,'empty search');shot('no-matches')
        ipc('activityProbe','query','Notification 17');wait(lambda:state()['rows']==1,'notification search includes final row')
        record('notification filtering reaches full history',state()['rows']==1,state())
        ipc('activityProbe','query','')
        click_control('dnd');wait(lambda:state()['dnd'],'DND toggle')
        record('native DND action preserved',state()['dnd'],state())
        ipc('activityProbe','tab','clipboard')
        ipc('activityProbe','select','text:Clipboard item 40');ipc('activityProbe','prepend');time.sleep(.3)
        record('selection stable on concurrent prepend',state()['selected']=='text:Clipboard item 40',state())
        click_control('remove')
        wait(lambda:state()['clips']==44,'remove selected concurrent entry')
        record('remove button never copies',state()['visible'] and state()['actions']==[],state())
        ipc('activityProbe','select','image:image-11.png');time.sleep(.15)
        click_control('row',273)
        wait(lambda:state()['removingImage'],'real image removal Process starts')
        record('overlapping image removal is rejected',ipc('activityProbe','removeImage','image-10.png').strip()=='false',state())
        wait(lambda:state()['images']==11 and not state()['removingImage'],'right-click removes image')
        record('right-click only removes image',state()['actions']==['removeImage:image-11.png'],state())
        ipc('activityProbe','select','text:Clipboard item 41');time.sleep(.15)
        click_control('copy');wait(lambda:not state()['visible'],'Copy closes popup')
        record('copy button dispatches exact selected text once',state()['actions']==['removeImage:image-11.png','copy:Clipboard item 41'],state())
        open_panel();ipc('activityProbe','select','image:image-10.png');time.sleep(.15)
        click_control('row');wait(lambda:not state()['visible'],'image row click copies and closes')
        record('image row copies once',state()['actions'][-1]=='copyImage:image-10.png',state())
        open_panel();click_control('clear')
        record('pointer clear requires confirmation',state()['clearArmed'] and state()['clips']==44,state())
        click_control('clear');wait(lambda:state()['rows']==0,'confirmed clear empties clipboard')
        record('clear invokes backend once',state()['actions'].count('clear')==1 and state()['images']==0 and state()['clips']==0,state())
        ipc('activityProbe','empty');wait(lambda:state()['rows']==0,'empty history');shot('empty')
        record('empty state clears stale selection',state()['selected']=='',state())
    finally:
        Path('/work/activity-final-state.json').write_text(json.dumps(state(),indent=2))
        if keys.poll() is None:keys.terminate();keys.wait(timeout=3)
