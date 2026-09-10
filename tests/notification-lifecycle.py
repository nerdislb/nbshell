"""Notification interaction probes, exclusively inside wayland-lifecycle's sandbox."""
import json
import os
from pathlib import Path
import re
import signal
import time


def instrument(shell):
    service = shell / 'Services/Notify.qml'
    service.write_text(service.read_text().replace('id: root', 'id: root\n    property var testToasts: []; property var testLayer: null; property var testMore: null; property var testKeys: []; property var testCenter: null', 1))
    popups = shell / 'Notifications/Popups.qml'
    popups.write_text(popups.read_text().replace('id: win', 'id: win\n        Component.onCompleted: Notify.testLayer = win', 1).replace('id: more', 'id: more\n                Component.onCompleted: Notify.testMore = more', 1))
    toast = shell / 'Notifications/NotificationToast.qml'
    text = toast.read_text().replace('id: root', '''id: root
    property bool testHovered: hover.hovered
    Component.onCompleted: Notify.testToasts = Notify.testToasts.concat([root])''', 1)
    text = text.replace('Component.onDestruction: {', 'Component.onDestruction: {\n        Notify.testToasts = Notify.testToasts.filter(t => t !== root);')
    toast.write_text(text)
    center = shell / 'Notifications/NotificationCenter.qml'
    center.write_text(center.read_text().replace('id: root', 'id: root\n    Component.onCompleted: Notify.testCenter = root\n    Component.onDestruction: Notify.testCenter = null', 1).replace('Keys.onPressed: event => {', 'Keys.onPressed: event => {\n            Notify.testKeys = Notify.testKeys.concat([event.key]);'))
    main = shell / 'shell.qml'
    text = main.read_text(); end = text.rfind('}')
    text = text[:end] + '''
    IpcHandler {
        target: "notificationProbe"
        function setup(): void { Config.set("notifyTimeout", 1800); }
        function corner(value: string): void { Config.set("notifyCorner", value); }
        function clear(): void { Notify.clear(); }
        function state(): string {
            return JSON.stringify({
                history: Notify.history.map(e => ({key:e.key, id:e.id, summary:e.summary, pending:Notify.popups.some(p=>p.key===e.key)})),
                popups: Notify.popups.map(e => ({key:e.key, id:e.id, summary:e.summary})),
                hover: Notify.popupHoverCounts,
                more: Notify.testMore ? {visible:Notify.testMore.visible, count:Notify.testLayer.overflowCount,x:Notify.testMore.mapToGlobal(0,0).x,y:Notify.testMore.mapToGlobal(0,0).y,w:Notify.testMore.width,h:Notify.testMore.height} : null,
                center: Runtime.notificationCenterOpen,
                keys: Notify.testKeys, query: Notify.testCenter ? Notify.testCenter.query : null,
                layer: Notify.testLayer ? {w:Notify.testLayer.width,h:Notify.testLayer.height,right:Notify.testLayer.margins.right,top:Notify.testLayer.margins.top,bottom:Notify.testLayer.margins.bottom,atTop:Notify.testLayer.atTop,sw:Notify.testLayer.screen.width,sh:Notify.testLayer.screen.height} : null,
                toasts: Notify.testToasts.map(t => { const p=t.mapToGlobal(0,0); return {key:t.entry.key,x:p.x,y:p.y,w:t.width,h:t.height,visible:t.visible,hover:t.testHovered}; })
            });
        }
    }
''' + text[end:]
    main.write_text(text)


def exercise(run, launch, wait, ipc, processes, shell, args):
    assert os.environ.get('NBSHELL_LIFECYCLE_TEST') == '1'
    assert not Path('/run/dbus/system_bus_socket').exists()
    assert os.environ['XDG_RUNTIME_DIR'] == '/run/test'
    assert os.environ['WAYLAND_DISPLAY'] == 'wayland-0'
    assert Path('/run/test/wayland-0').is_socket()
    results = []
    def record(name, passed, detail=''):
        results.append({'test':name, 'passed':bool(passed), 'detail':detail})
        Path('/work/notification-results.json').write_text(json.dumps(results, indent=2))
    def state():
        value=json.loads(ipc('notificationProbe','state'))
        layer=value.get('layer')
        if layer:
            for t in value['toasts'] + ([value['more']] if value.get('more') else []):
                t['x'] += layer['sw']-layer['w']-layer['right']
                t['y'] += layer['top'] if layer['atTop'] else layer['sh']-layer['h']-layer['bottom']
        return value
    def send(title, old=0, body='Notification contract fixture', actions=False, urgency=1):
        value = run(['gdbus','call','--session','--dest','org.freedesktop.Notifications',
            '--object-path','/org/freedesktop/Notifications','--method','org.freedesktop.Notifications.Notify',
            'ContractTest',str(old),'',title,body,'["default", "Open"]' if actions else '[]',
            "{'urgency': <byte " + str(urgency) + '>}', '1']).stdout
        return int(re.search(r'uint32 (\d+)', value)[1])
    def pointer(*commands):
        run(['/test-bin/pointer-client',str(args.width),str(args.height),*map(str,commands)])
    def move_toast():
        t=state()['toasts'][0]
        pointer('move',round((t['x']+t['w']/2)*args.scale),round((t['y']+t['h']/2)*args.scale),'pause',100)
    def shot(name): run(['grim','/work/'+name+'.png'])
    ipc('notificationProbe','setup');ipc('notificationProbe','corner',args.notification_corner);ipc('notificationProbe','clear')
    ident=send('Hover 0')
    wait(lambda: len(state()['toasts']) == 1, 'hover toast')
    record('hover initial geometry',True,state())
    shot('hover-before')
    move_toast()
    shot('hover-pointer')
    wait(lambda: bool(state()['toasts']) and state()['toasts'][0]['hover'], 'real pointer hover')
    for i in range(1,21):
        send('Hover '+str(i),ident);time.sleep(.04)
    time.sleep(3.0)
    s=state();record('updates while hovered',len(s['popups'])==1 and s['popups'][0]['summary']=='Hover 20',s)
    shot('hover-updated')
    pointer('move',5,args.height-5)
    wait(lambda: not state()['popups'], 'expiry after real hover exit')
    record('hover exit expires without leaked counter',not state()['hover'])

    monitor=launch(['dbus-monitor','--session',"type='signal',interface='org.freedesktop.Notifications',member='ActionInvoked'"], 'notification-actions.log')
    ident=send('Action before',actions=True);send('Action after',ident,actions=True)
    wait(lambda: len(state()['toasts'])==1 and state()['popups'][0]['summary']=='Action after','action update')
    move_toast();pointer('click',272,'pause',200)
    wait(lambda: not state()['popups'],'action closes toast')
    action_pattern = r'uint32 ' + str(ident) + r'\s+string "default"'
    wait(lambda: bool(re.search(action_pattern, Path('/work/notification-actions.log').read_text())), 'matching action signal')
    record('updated default action invoked',True,{'id':ident,'action':'default'})
    ident=send('Dismiss before');send('Dismiss after',ident)
    wait(lambda:len(state()['toasts'])==1,'dismiss toast');move_toast();pointer('click',273,'pause',200)
    wait(lambda: not state()['popups'], 'right-click close')
    record('right click dismisses updated toast',not state()['popups'])
    pointer('move',5,args.height-5)

    ipc('notificationProbe','clear')
    for i in range(8): send('Burst '+str(i),urgency=2)
    wait(lambda:len(state()['popups'])==5,'bounded stack')
    s=state();record('eight notifications retain full history and five popups',len(s['history'])==8 and len(s['popups'])==5,s)
    shot('burst-eight')
    ipc('notificationProbe','clear')
    ident=send('Restart before',urgency=2);send('Restart latest',ident,urgency=2)
    wait(lambda:state()['history'][0]['summary']=='Restart latest','latest before restart')
    key=state()['history'][0]['key']
    wait(lambda:any(e['key']==key and e['summary']=='Restart latest' for e in json.loads(Path('/home/user/.local/state/nbshell/notifications.json').read_text())), 'persist latest before restart')
    assert os.getpgid(shell.pid) == shell.pid and shell.pid != os.getpgrp()
    os.killpg(shell.pid,signal.SIGTERM);shell.wait(timeout=5);processes.remove(shell)
    shell=launch(['/test-bin/qs','-p','/work/shell','--no-color'],'shell-restarted.log')
    wait(lambda:run(['/test-bin/qs','-p','/work/shell','ipc','call','notificationProbe','state'],False).returncode==0,'restarted shell IPC')
    wait(lambda:len(state()['popups'])==1,'restored popup')
    s=state();record('restart restores latest snapshot once',len(s['history'])==1 and s['popups'][0]['summary']=='Restart latest' and s['popups'][0]['key']==key,s)
    new=send('New server generation',urgency=2)
    wait(lambda:len(state()['popups'])==2,'new generation')
    while new < ident:
        new=send('New server generation '+str(new+1),urgency=2)
    s=state()
    record('new server IDs do not overwrite restored history',new==ident and len(s['history'])==ident+1 and any(e['key']==key and e['summary']=='Restart latest' for e in s['history']),{'restoredId':ident,'newId':new})

    ipc('notificationProbe','clear')
    send('Geometry and long content',0,body='Long text remains readable and within its notification. '*18,urgency=2)
    wait(lambda:len(state()['toasts'])==1,'geometry toast')
    s=state();w=args.width/args.scale;h=args.height/args.scale
    record('single long toast fits logical output',all(t['x']>=0 and t['y']>=0 and t['x']+t['w']<=w+1 and t['y']+t['h']<=h+1 for t in s['toasts'] if t['visible']),s)
    shot('long-content')
    target=Path('/work/keyboard-target');target.mkdir()
    (target/'shell.qml').write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\nShellRoot { Window { visible:true; width:240; height:120; title: "Notification keyboard target"; TextInput { id: field; anchors.fill:parent; focus:true } } IpcHandler { target: "keyboardTarget"; function text(): string {return field.text;} } }')
    launch(['/test-bin/qs','-p',str(target)],'keyboard-target.log')
    wait(lambda:any(w['title']=='Notification keyboard target' for w in json.loads(run(['/test-bin/umbriel','windows','--json']).stdout)),'keyboard target window')
    keyboard=launch(['/test-bin/pointer-client',str(args.width),str(args.height),'pause','1200','tap','15','pause','1000','tap','1','pause','300','tap','30','pause','200'], 'keyboard.log')
    processes.remove(keyboard)
    time.sleep(.2)
    ipc('notify','center')
    wait(lambda:state()['center'],'center opened')
    time.sleep(1.3);shot('keyboard-tab')
    record('Tab keeps center open and reaches key handler',state()['center'] and 16777217 in state()['keys'])
    keyboard.wait(timeout=5)
    wait(lambda:not any(l['namespace']=='nbshell:notification-center' and l['mapped'] for l in json.loads(run(['/test-bin/umbriel','layers','--json']).stdout)), 'center unmapped after Escape')
    record('Escape closes notification center',not state()['center'] and 16777216 in state()['keys'],state())
    record('focus returns to previous application',run(['/test-bin/qs','-p',str(target),'ipc','call','keyboardTarget','text']).stdout.strip()=='a')
    if state()['center']: ipc('notify','center')
    ipc('notificationProbe','clear')
    for i in range(5):send('Tall stack '+str(i),body='Long wrapped body text. '*35,urgency=2)
    wait(lambda:len(state()['toasts'])==5,'tall stack')
    s=state();record('five long toasts fit output',all(t['y']>=0 and t['y']+t['h']<=min(h,(s['layer']['top'] if s['layer']['atTop'] else s['layer']['sh']-s['layer']['h']-s['layer']['bottom'])+s['layer']['h'])+1 for t in s['toasts'] if t['visible']),s)
    shot('tall-stack')
    more=s['more']; visible=[t for t in s['toasts'] if t['visible']]
    record('overflow indicator accounts for hidden cards',more['visible'] and more['count']==5-len(visible) and more['count']>0)
    footer_x=more['x']+more['w']/2
    footer_y=more['y']+more['h']/2
    pointer('move',round(footer_x*args.scale),round(footer_y*args.scale),'click',272,'pause',300)
    record('overflow opens complete history',state()['center'] and len(state()['history'])==5)
    shot('overflow-history')
    if state()['center']:ipc('notify','center')
    ipc('notificationProbe','clear')
    record('test configuration',True,{'width':args.width,'height':args.height,'scale':args.scale,'theme':args.theme})
    print(json.dumps(results))
    if any(not r['passed'] for r in results):
        raise AssertionError('Notification contract findings; see notification-results.json')
