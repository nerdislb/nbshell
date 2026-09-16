"""Real calculator input, clipboard and window lifecycle on a private Wayland seat."""
import json
import re
import subprocess
import time
from pathlib import Path


def instrument(shell):
    # Exercise the shipped floating policy, not the harness's default tiled layout.
    policy=(Path('/source/umbriel/nbshell.toml').read_text().split('match.title = "^nbshell Calculator$"')[1].split('[[window_rule]]')[0])
    with Path('/work/umbriel.toml').open('a') as f:
        f.write('\n[[window_rule]]\nmatch.title = "^nbshell Calculator$"'+policy)
    p=shell/'Common/Runtime.qml';s=p.read_text();i=s.index('{');s=s[:i+1]+'\n    property bool calculatorTestMounted: false\n'+s[i+1:];p.write_text(s)
    p=shell/'Calculator/CalculatorWindow.qml';s=p.read_text().replace('    id: root','''    id: root
    QtObject { Component.onCompleted: Runtime.calculatorTestMounted=true }
    Component.onDestruction: Runtime.calculatorTestMounted=false''',1);end=s.rfind('}')
    s='import Quickshell.Io\n'+s[:end]+'''
    function testRect(item) {const p=item.mapToItem(root.contentItem,0,0);return {x:p.x,y:p.y,w:item.width,h:item.height};}
    IpcHandler {
        target:"calculatorProbe"
        function state():string {
            const f=keys.Window.window.activeFocusItem;
            return JSON.stringify({expression:root.expression,result:root.result,previous:root.previous,
                evaluated:root.evaluated,invalid:root.invalid,width:root.width,height:root.height,
                focus:f?.accessibleName||"",inputFocus:input.activeFocus,copyEnabled:copyLabel.enabled,
                copy:root.testRect(copyLabel),keypad:root.testRect(keypad),footer:root.testRect(footer),
                display:root.testRect(display),contentHeight:display.contentHeight,scroll:display.contentY,
                expressionHeight:expressionLabel.height,expressionLines:expressionLabel.lineCount,
                names:Array.from({length:buttons.count},(_,i)=>buttons.itemAt(i).accessibleName),
                buttons:Array.from({length:buttons.count},(_,i)=>root.testRect(buttons.itemAt(i)))});
        }
        function expression(value:string):void {root.expression=value;root.evaluated=false;root.preview();}
        function accessibleKey(index:int):void {buttons.itemAt(index).Accessible.pressAction();}
        function accessibleCopy():void {copyLabel.Accessible.pressAction();}
        function focusInput():void {input.forceActiveFocus();}
        function focusCopy():void {copyLabel.forceActiveFocus();}
        function repeatKey(index:int):void {buttons.itemAt(index).activateFromKey({isAutoRepeat:true,accepted:false});}
    }
'''+s[end:];p.write_text(s)
    p=shell/'shell.qml';s=p.read_text();end=s.rfind('}')
    s=s[:end]+'''
    IpcHandler {
        target:"calculatorFixture"
        function state():string {return JSON.stringify({open:Runtime.calculatorOpen,mounted:Runtime.calculatorTestMounted});}
    }
'''+s[end:];p.write_text(s)


def exercise(run,launch,wait,ipc,processes,shell,args):
    results=[]
    def state():return json.loads(ipc('calculatorProbe','state'))
    def service():return json.loads(ipc('calculatorFixture','state'))
    def record(name,ok):
        results.append(dict(test=name,passed=bool(ok)))
        Path('/work/calculator-results.json').write_text(json.dumps(results,indent=2))
        if not ok:print('FAILED STATE',state() if service()['mounted'] else service(),flush=True)
        assert ok,name
    def pointer(*cmd):run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,cmd)])
    launch(['/test-bin/pointer-client',str(args.width),str(args.height),'mod','none','pause','120000'],'calculator-seat.log')
    def key(code,mod=None):pointer('pause',50,*(['mod',mod] if mod else []),'tap',code,*(['mod','none'] if mod else []),'pause',100)
    def shot(name):time.sleep(.15);run(['grim','/work/calculator-'+name+'.png'])
    def set_expression(value):ipc('calculatorProbe','expression',value);time.sleep(.1)
    def clipboard():return run(['wl-paste','--no-newline'],False).stdout
    def window():return next(w for w in json.loads(run(['/test-bin/umbriel','windows','--json']).stdout) if w['title']=='nbshell Calculator')
    def click_rect(rect):
        w=window();pointer('move',round((w['x']+rect['x']+rect['w']/2)*args.scale),round((w['y']+rect['y']+rect['h']/2)*args.scale),'click',272,'pause',120)
    def open_menu():ipc('calculator','open');wait(lambda:service()['mounted'],'calculator mapped');time.sleep(.25)
    def closed():return not service()['mounted'] and not service()['open']
    def fits():
        s=state();w=window();f=s['footer'];k=s['keypad']
        return w['x']>=0 and w['y']>=0 and w['x']+w['w']<=args.width/args.scale and w['y']+w['h']<=args.height/args.scale and f['y']+f['h']<=s['height'] and k['h']>0 and all(b['w']>0 and b['h']>=20 and b['y']+b['h']<=f['y'] for b in s['buttons'])
    target=Path('/work/calculator-focus-target');target.mkdir()
    (target/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {property var received:[]
 FloatingWindow {visible:true;implicitWidth:300;implicitHeight:120;title:"Calculator focus test"
 Item {id:sink;anchors.fill:parent;focus:true;Keys.onPressed:e=>{received=received.concat([e.key]);e.accepted=true;}}}
 IpcHandler {target:"probe";function state():string{return JSON.stringify({focused:sink.activeFocus,keys:received});}}
}''')
    launch(['/test-bin/qs','-p',str(target)],'calculator-focus-target.log')
    def underlying():
        r=run(['/test-bin/qs','-p',str(target),'ipc','call','probe','state'],False)
        return json.loads(r.stdout) if r.returncode==0 else {'focused':False,'keys':[]}
    wait(lambda:underlying()['focused'],'underlying focus');open_menu()
    record('all twenty keypad actions retained',state()['names']==['Clear','(',')','Divide','7','8','9','Multiply','4','5','6','Subtract','1','2','3','Add','Toggle sign','0','Decimal point','Equals'])
    record('normal floating window starts within output',window()['floating'] and fits())
    record('keyboard input initially focused',state()['inputFocus']);shot('initial')
    key(3);key(78);key(4);key(55);key(5)
    record('keyboard operators preserve precedence',state()['expression']=='2+3×4' and state()['result']=='14')
    key(28);record('Enter commits expression and history',state()['evaluated'] and state()['expression']=='14' and state()['previous']=='2+3×4 =');shot('result')
    key(78);key(3);key(28);record('operator continues from evaluated result',state()['result']=='16')
    key(6);record('digit starts fresh after equals',state()['expression']=='5' and state()['result']=='5')
    key(14);record('Backspace clears last character',state()['expression']=='0')
    key(7);key(52);key(6);record('decimal input works',state()['result']=='6.5')
    key(46,'ctrl');wait(lambda:clipboard()=='6.5','real clipboard copy');record('Ctrl+C copies actual result',clipboard()=='6.5')
    key(38,'ctrl');record('Ctrl+L clears all calculator state',state()['expression']=='0' and state()['result']=='0' and state()['previous']=='')
    key(15);record('Tab reaches Copy first',state()['focus']=='Copy result')
    key(15);record('Tab reaches first keypad control',state()['focus']=='Clear');shot('focus')
    key(15);key(57);record('Space activates focused parenthesis',state()['expression']=='(' and state()['invalid'])
    ipc('calculatorProbe','repeatKey','1');record('held activation does not repeat a keypad action',state()['expression']=='(')
    key(15);key(28);record('Enter activates focused keypad control',state()['expression']=='()')
    for _ in range(17):key(15)
    record('Tab follows all keypad controls in visual order',state()['focus']=='Equals')
    key(15);record('disabled Copy is skipped by Tab',state()['focus']=='Clear')
    key(57);record('Clear via keyboard restores valid input',state()['expression']=='0' and not state()['invalid'])
    ipc('calculatorProbe','focusInput');click_rect(state()['buttons'][12]);click_rect(state()['buttons'][15]);click_rect(state()['buttons'][13]);click_rect(state()['buttons'][19])
    record('pointer calculation converges with keyboard actions',state()['result']=='3' and state()['evaluated'] and state()['inputFocus'])
    ipc('calculatorProbe','accessibleKey','16');record('accessible sign retains arithmetic parser',state()['result']=='-3')
    ipc('calculatorProbe','accessibleCopy');wait(lambda:clipboard()=='-3','accessible clipboard');record('accessible Copy uses actual clipboard',clipboard()=='-3')
    set_expression('(12,5+7.5)×50%');record('parentheses comma and percent retained',state()['result']=='10')
    ipc('calculatorProbe','focusCopy');set_expression('1÷0');record('division by zero shows invalid and disables Copy',state()['invalid'] and not state()['copyEnabled']);shot('invalid');record('invalidating focused Copy returns to expression input',state()['inputFocus'])
    key(46,'ctrl');ipc('calculatorProbe','accessibleCopy');key(28)
    record('invalid keyboard and accessible copy leave clipboard unchanged',clipboard()=='-3' and state()['invalid'] and not state()['evaluated'])
    key(111);record('Delete recovers from invalid input',state()['expression']=='0' and state()['copyEnabled'])
    click_rect(state()['copy']);wait(lambda:clipboard()=='0','pointer clipboard');record('pointer Copy uses same result action',clipboard()=='0')
    set_expression('+'.join(['123456789']*35));record('long expressions wrap instead of disappearing',state()['expressionLines']>5 and state()['contentHeight']>state()['display']['h'])
    record('long expression initially reveals result',state()['scroll']>0);shot('long-end')
    key(104);record('PageUp reveals earlier expression content',state()['scroll']<state()['contentHeight']-state()['display']['h']);shot('long-start')
    key(109);record('PageDown reveals latest result',state()['scroll']>0)
    set_expression('<b>literal</b>');record('invalid text is displayed literally',state()['invalid']);shot('literal')
    initial_size=state();run(['/test-bin/umbriel','msg','window-set-width:0.1']);run(['/test-bin/umbriel','msg','window-set-height:0.1']);time.sleep(.3);record('minimum window keeps every keypad row and footer visible',fits() and state()['width']<initial_size['width'] and state()['height']<initial_size['height']);shot('minimum')
    key(1);wait(closed,'Escape closes');key(30)
    record('Escape restores prior application focus',underlying()['focused'] and underlying()['keys']==[65])
    open_menu();record('reopen starts a clean calculator',state()['expression']=='0' and state()['inputFocus'])
    ipc('calculator','toggle');wait(closed,'toggle closes');open_menu();ipc('calculator','close');wait(closed,'IPC closes')
    record('IPC close and toggle retain lifecycle',closed())
    log=Path('/work/shell.log').read_text()
    record('no QML type or binding errors',not re.search(r'Binding loop|ReferenceError|TypeError|Unable to assign|Cannot assign|is not a type',log))
    print(json.dumps(results))
