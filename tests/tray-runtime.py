#!/usr/bin/env python3
"""Exercise real Quickshell DBusMenu levels on a private session bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[1]
if '--private-bus' not in sys.argv:
    sys.exit(subprocess.call(['dbus-run-session', '--', sys.executable, __file__, '--private-bus']))

with tempfile.TemporaryDirectory(prefix='nbshell-tray-test-') as directory:
    base = Path(directory)
    shell = base / 'shell'; shell.mkdir()
    for name in ['Common', 'Widgets', 'scripts']:
        (shell / name).symlink_to(ROOT / 'shell' / name)
    settings = base/'config/nbshell'; settings.mkdir(parents=True)
    (settings/'themes').symlink_to(ROOT/'themes')
    (shell / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Widgets
ShellRoot {
 FloatingWindow {
  id: window
  visible: true; implicitWidth: 400; implicitHeight: 480; color: Theme.bg
  Item { id: captureRoot; anchors.fill: parent
  Rectangle { anchors.fill: parent; color: Theme.bg }
  Item { id: popupAnchor; width: 20; height: 20; x: 380; y: 460 }
  MenuView { id: menu; width: implicitWidth; height: implicitHeight
   handle: SystemTray.items.values.length ? SystemTray.items.values[0].menu : null
  }
  }
 }
 Popout {
  id: popup
  anchorItem: popupAnchor
  maximumContentHeight: 100
  minimumContentHeight: 6 * Theme.rowHeight
  contentComponent: Component {
   MenuView { handle: SystemTray.items.values.length ? SystemTray.items.values[0].menu : null }
  }
 }
 IpcHandler {
  target: "test"
  function status(): string { return JSON.stringify({items:SystemTray.items.values.length, icons:SystemTray.items.values.map(x=>x.icon), depth:menu.stack.length, popupHeight:popup.lockedContentHeight,
   children:menu.currentChildren.map(x=>({text:x.text,enabled:x.enabled,hasChildren:x.hasChildren})),
   icon:Quickshell.iconPath("folder",true)}); }
  function openPopup(): void { popup.open(); }
  function closePopup(): void { popup.closeImmediately(); }
  function enter(index: int): void { menu.enter(menu.currentChildren[index]); }
  function back(): void { menu.leave(); }
  function appearance(light: bool): void { Config.theme = light ? "nblight" : "tokyo-night"; menu.rowWidth = light ? 240 : 320; }
  function capture(path: string): void { captureRoot.grabToImage(result => result.saveToFile(path)); }
  function activate(index: int): void { menu.firstFocusableItem(menu.currentChildren[index])?.activate(); }
 }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               XDG_RUNTIME_DIR=str(base/'runtime'), XDG_CONFIG_HOME=str(base/'config'),
               QS_ICON_THEME='Adwaita')
    env.pop('WAYLAND_DISPLAY', None); env.pop('DISPLAY', None)
    Path(env['XDG_RUNTIME_DIR']).mkdir(mode=0o700)
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    props = {'Id': GLib.Variant('s','nbshell-regression'), 'Title': GLib.Variant('s','Tray regression'),
             'Status':GLib.Variant('s','Active'),'Category':GLib.Variant('s','ApplicationStatus'),
             'IconName':GLib.Variant('s','folder'),'ItemIsMenu':GLib.Variant('b',True),'Menu':GLib.Variant('o','/Menu')}
    prop_xml=''.join(f'<property name="{k}" type="{v.get_type_string()}" access="read"/>' for k,v in props.items())
    sni=Gio.DBusNodeInfo.new_for_xml('<node><interface name="org.kde.StatusNotifierItem">'+prop_xml+'</interface></node>').interfaces[0]
    bus.register_object('/Item',sni,None,lambda c,s,p,i,n:props.get(n),None)
    menu_xml='''<node><interface name="com.canonical.dbusmenu">
<method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/><arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
<method name="GetGroupProperties"><arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
<method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
<method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
<signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
<property name="Version" type="u" access="read"/>
</interface></node>'''
    labels={0:'root',1:'First submenu',2:'Disabled',3:'Root action',11:'Deep submenu',12:'Child action',21:'Deep action'}
    children={0:[1,2,3],1:[11,12],11:[21]}
    events=[]
    def properties(index):
        result={'label':GLib.Variant('s',labels[index]),'enabled':GLib.Variant('b',index!=2),'visible':GLib.Variant('b',True)}
        if index in children: result['children-display']=GLib.Variant('s','submenu')
        return result
    def layout(index):
        return (index,properties(index),[GLib.Variant('(ia{sv}av)',layout(child)) for child in children.get(index,[])])
    def method(c,s,p,i,name,params,inv):
        args=params.unpack()
        if name=='GetLayout': inv.return_value(GLib.Variant('(u(ia{sv}av))',(1,layout(args[0]))))
        elif name=='GetGroupProperties': inv.return_value(GLib.Variant('(a(ia{sv}))',([(x,properties(x)) for x in args[0]],)))
        elif name=='AboutToShow': inv.return_value(GLib.Variant('(b)',(False,)))
        elif name=='Event': events.append(args[:2]);inv.return_value(None)
    bus.register_object('/Menu',Gio.DBusNodeInfo.new_for_xml(menu_xml).interfaces[0],method,
                        lambda c,s,p,i,n:GLib.Variant('u',3) if n=='Version' else None,None)
    context=GLib.MainContext.default()
    def pump():
        while context.pending(): context.iteration(False)
    def command(method,*args):
        proc=subprocess.Popen(['qs','ipc','-p',str(shell),'call','test',method,*map(str,args)],env=env,
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        end=time.monotonic()+5
        while proc.poll() is None and time.monotonic()<end: pump();time.sleep(.01)
        if proc.poll() is None: proc.kill();raise AssertionError('IPC timeout')
        output=proc.communicate()[0]
        if proc.returncode: raise RuntimeError(output)
        return output.strip()
    def wait(predicate):
        end=time.monotonic()+8
        while time.monotonic()<end:
            pump()
            try:
                state=json.loads(command('status'))
                if predicate(state): return state
            except (RuntimeError,json.JSONDecodeError): pass
            time.sleep(.02)
        raise AssertionError('State did not converge')
    def capture(name):
        directory = os.environ.get('NBSHELL_TRAY_TEST_OUTPUT')
        if not directory: return
        destination = Path(directory); destination.mkdir(parents=True, exist_ok=True)
        (destination / (name + '.png')).unlink(missing_ok=True)
        command('capture', str(destination / (name + '.png')))
        end = time.monotonic() + 3
        while time.monotonic() < end and not (destination / (name + '.png')).exists(): pump(); time.sleep(.02)
        assert (destination / (name + '.png')).is_file()

    with (base/'log').open('w') as log:
        proc=subprocess.Popen(['qs','-p',str(shell)],env=env,stdout=log,stderr=subprocess.STDOUT)
        try:
            wait(lambda s: True)
            command('openPopup')
            empty_height = wait(lambda s:s['popupHeight'] > 0)['popupHeight']
            bus.call_sync('org.kde.StatusNotifierWatcher','/StatusNotifierWatcher','org.kde.StatusNotifierWatcher',
                          'RegisterStatusNotifierItem',GLib.Variant('(s)',('/Item',)),None,Gio.DBusCallFlags.NONE,5000,None)
            initial=wait(lambda s:len(s['children'])==3)
            wait(lambda s: s['popupHeight'] == empty_height == 100)
            command('closePopup')
            print('SNI icon sources:',initial['icons'])
            capture('root-dark')
            command('activate',1); assert not any(e[1]=='clicked' for e in events),'Disabled entry activated'
            command('enter',0);wait(lambda s:s['depth']==1 and len(s['children'])==2)
            command('enter',0);wait(lambda s:s['depth']==2 and len(s['children'])==1)
            capture('deep-dark')
            command('back');wait(lambda s:s['depth']==1 and len(s['children'])==2)
            command('enter',0);wait(lambda s:s['depth']==2 and len(s['children'])==1)
            command('appearance','true'); time.sleep(.2); capture('deep-light-small')
            command('activate',0)
            end=time.monotonic()+2
            while time.monotonic()<end and (21,'clicked') not in events: pump();time.sleep(.01)
            assert (21,'clicked') in events, events
            command('back');command('back');wait(lambda s:s['depth']==0 and len(s['children'])==3)
            command('enter',0);wait(lambda s:s['depth']==1)
            children[0]=[2,3]
            bus.emit_signal(None,'/Menu','com.canonical.dbusmenu','LayoutUpdated',GLib.Variant('(ui)',(2,0)))
            wait(lambda s:s['depth']==0 and len(s['children'])==2)
            print('PASS: real DBusMenu nested navigation, disabled guard, correct action, parent removal, stable asynchronous popup viewport')
        finally:
            proc.terminate();proc.wait(timeout=5)
            output=(base/'log').read_text()
            if os.environ.get('NBSHELL_TRAY_TEST_OUTPUT'):
                (Path(os.environ['NBSHELL_TRAY_TEST_OUTPUT'])/'qml-runtime.log').write_text(output)
            if any(word in output for word in ['TypeError:', 'ReferenceError:', 'ERROR:']):
                print(output);raise AssertionError('QML runtime errors')
