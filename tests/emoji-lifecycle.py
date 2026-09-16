"""Emoji picker on a private Wayland seat, including real isolated clipboard IO."""
import json
import re
import subprocess
import time
from pathlib import Path


def instrument(shell):
    p=shell/'Common/Runtime.qml';s=p.read_text();i=s.index('{');s=s[:i+1]+'''
    property var emojiTestCalls: []
    property bool emojiTestMounted: false
'''+s[i+1:];p.write_text(s)
    p=shell/'Menu/EmojiWindow.qml';s=p.read_text()
    s=s.replace('    id: root','''    id: root
    QtObject { Component.onCompleted: Runtime.emojiTestMounted=true }
    Component.onDestruction: Runtime.emojiTestMounted=false''',1)
    s=s.replace('function copyEmoji(emoji) {', 'function copyEmoji(emoji) { Runtime.emojiTestCalls=Runtime.emojiTestCalls.concat([emoji]);')
    end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    function testRect(item) {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
    IpcHandler {
        target:"emojiProbe"
        function state():string {
            const item=grid.currentItem,f=search.Window.window.activeFocusItem;
            return JSON.stringify({query:root.query,key:root.selectedKey,index:root.selected,
                total:root.catalog.length,shown:root.shown.length,columns:root.columns,
                focus:f?.accessibleName||"",searchFocused:search.activeFocus,
                row:item?root.testRect(item):{},grid:root.testRect(grid),box:root.testRect(box),footer:root.testRect(footer),
                contentHeight:grid.contentHeight,cursor:search.cursorPosition,selectedText:search.selectedText,scroll:grid.contentY,
                rowVisible:!!item && item.y>=grid.contentY-1 && item.y+item.height<=grid.contentY+grid.height+1});
        }
        function query(value:string):void {search.text=value;root.focusSearch(false);}
        function choose(value:string):void {root.choose(value);}
        function repeatEnter():void {grid.currentItem?.activateFromKey({isAutoRepeat:true,accepted:false});}
        function accessiblePress():void {grid.currentItem.Accessible.pressAction();}
        function rowRect(index:int):string {const item=grid.itemAtIndex(index);return JSON.stringify(item?root.testRect(item):{});}
    }
'''+s[end:];p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"emojiFixture"
        function state():string {return JSON.stringify({calls:Runtime.emojiTestCalls,open:Runtime.emojiOpen,mounted:Runtime.emojiTestMounted});}
        function reset():void {Runtime.emojiTestCalls=[];}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('emojiProbe','state'))
    def service():return json.loads(ipc('emojiFixture','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/emoji-results.json').write_text(json.dumps(results,indent=2))
        if not ok: print('FAILED STATE',state() if service()['mounted'] else service(),flush=True)
        assert ok,(name,service())
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','120000'],'emoji-seat.log')
    def key(code,mod=None):pointer('pause',50,*(['mod',mod] if mod else []),'tap',code,*(['mod','none'] if mod else []),'pause',100)
    def shot(name):time.sleep(.15);run(['grim','/work/emoji-'+name+'.png'])
    def open_menu():
        ipc('emoji','open');wait(lambda:service()['mounted'],'emoji mapped');time.sleep(.15)
    def closed():return not service()['mounted'] and not service()['open']
    def clipboard():
        r=run(['wl-paste','--no-newline'],False);return r.stdout if r.returncode==0 else None
    def query(value):ipc('emojiProbe','query',value);time.sleep(.12)
    target=Path('/work/emoji-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Emoji focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'emoji-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus')
    open_menu();s=state();b=s['box'];f=s['footer']
    record('all 69 emoji entries retained',s['total']==69 and s['shown']==69)
    record('opens with native search focus and first selection',s['searchFocused'] and s['key']=='😀')
    record('card and footer fit output',b['x']>=0 and b['y']>=0 and b['x']+b['w']<=args.width/args.scale and b['y']+b['h']<=args.height/args.scale and f['y']+f['h']<=b['y']+b['h'])
    record('adaptive grid has at least one column',s['columns']>=1);shot('initial')
    key(15);record('Tab enters selected cell',not state()['searchFocused'] and state()['focus']=='Grinning face 😀')
    key(106);record('Right selects next emoji',state()['index']==1 and state()['focus']=='Tears of joy 😂')
    key(108);record('Down moves by actual column count',state()['index']==1+state()['columns'])
    key(107);record('End reveals final cell',state()['key']=='🇩🇪' and state()['rowVisible'] and (state()['contentHeight']<=state()['grid']['h'] or state()['scroll']>0));shot('last')
    key(105);record('Left reaches penultimate compound flag',state()['key']=='🇦🇹' and state()['rowVisible'])
    key(102);key(105);record('Left wraps first to final emoji',state()['key']=='🇩🇪')
    key(106);record('Right wraps final to first emoji',state()['key']=='😀')
    key(109);record('PageDown navigates and reveals selection',state()['index']>0 and state()['rowVisible'])
    key(104);record('PageUp returns toward first cell',state()['index']==0 and state()['rowVisible'])
    ipc('emojiProbe','repeatEnter');record('autorepeat cannot activate a cell',service()['open'] and service()['calls']==[])
    key(15);record('Tab returns to search',state()['searchFocused'])
    # Physical typing, native caret editing, Ctrl+A and clipboard paste.
    for code in [46,24,33,33,18,18]:key(code)
    record('English search through real typing',state()['query']=='coffee' and state()['key']=='☕' and state()['shown']==1)
    key(105);record('Left moves native caret without grid navigation',state()['cursor']==5 and state()['key']=='☕')
    key(30,'ctrl');record('Ctrl+A selects native query',state()['selectedText']=='coffee')
    subprocess.run(['wl-copy','--','gruen'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=5);key(47,'ctrl')
    record('Ctrl+V replaces selected query and German alias works',state()['query']=='gruen' and state()['key']=='💚' and state()['shown']==1)
    key(1);record('Escape clears query without closing',state()['query']=='' and state()['shown']==69 and service()['open'])
    query('no-such-emoji <b>literal</b>');record('empty search clears selection',state()['shown']==0 and state()['key']=='');shot('empty')
    key(28);key(108);record('empty search cannot copy or lose search focus',service()['calls']==[] and state()['searchFocused'])
    key(1);key(108);key(33,'ctrl');record('Ctrl+F returns from grid to native editor',state()['searchFocused'])
    query('herz');record('original German multi-match keywords retained',state()['shown']==6)
    query('austria');key(28);wait(closed,'Enter copies flag');wait(lambda:clipboard()=='🇦🇹','real flag clipboard')
    record('Enter copies exact compound flag once',service()['calls']==['🇦🇹'])
    record('copy close restores application focus',underlying()['focused'])
    ipc('emojiFixture','reset');open_menu();record('reopen clears query and selection',state()['query']=='' and state()['key']=='😀' and state()['searchFocused'])
    query('victory');key(15);key(57);wait(closed,'Space copies');wait(lambda:clipboard()=='✌️','variation sequence clipboard')
    record('Space copies complete variation-selector sequence once',service()['calls']==['✌️'])
    ipc('emojiFixture','reset');open_menu();query('robot');ipc('emojiProbe','accessiblePress');wait(closed,'accessible copies');wait(lambda:clipboard()=='🤖','accessible clipboard')
    record('accessibility activation shares real copy path',service()['calls']==['🤖'])
    ipc('emojiFixture','reset');open_menu();query('coffee');ipc('emojiProbe','choose','😀')
    record('stale filtered-out emoji cannot copy',service()['calls']==[] and service()['open'])
    query('');p=json.loads(ipc('emojiProbe','rowRect','1'));x=round((p['x']+p['w']/2)*args.scale);y=round((p['y']+p['h']/2)*args.scale)
    pointer('move',x,y,'pause',80,'move',x+4,y,'pause',100)
    record('hover updates copy target without stealing text focus',state()['key']=='😂' and state()['searchFocused'])
    key(28);wait(closed,'hover then Enter');wait(lambda:clipboard()=='😂','hover clipboard')
    record('Enter after hover copies indicated emoji',service()['calls']==['😂'])
    ipc('emojiFixture','reset');open_menu();query('heart');shot('search');p=json.loads(ipc('emojiProbe','rowRect','1'))
    pointer('move',round((p['x']+p['w']/2)*args.scale),round((p['y']+p['h']/2)*args.scale),'click',272,'pause',100)
    wait(closed,'pointer copies');wait(lambda:clipboard()=='🥰','pointer clipboard')
    record('pointer copy uses exact cell once',service()['calls']==['🥰'])
    ipc('emojiFixture','reset');open_menu();query('coffee');key(1);key(1);wait(closed,'Escape clears then closes');key(30)
    record('Escape restores application keyboard focus without copy',service()['calls']==[] and underlying()['focused'] and underlying()['keys']==[65])
    open_menu();pointer('move',2,2,'click',272,'pause',100);wait(closed,'outside close')
    record('outside click closes without modifying clipboard',service()['calls']==[] and clipboard()=='🥰')
    open_menu();query('heart');ipc('emoji','close');wait(closed,'IPC closes');open_menu()
    record('IPC reopen resets search',state()['query']=='' and state()['searchFocused'])
    ipc('emoji','close');wait(closed,'final close')
    log=Path('/work/shell.log').read_text()
    record('no QML binding or type errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
