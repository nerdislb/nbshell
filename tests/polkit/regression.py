import os, sys, subprocess, dbus, dbus.service
from pathlib import Path
ARTIFACTS = Path(__file__).resolve().parent
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
bus=dbus.SessionBus()
loop=GLib.MainLoop()
class Authority(dbus.service.Object):
 def __init__(self):
  self.name=dbus.service.BusName('org.freedesktop.PolicyKit1',bus)
  super().__init__(bus,'/org/freedesktop/PolicyKit1/Authority')
 @dbus.service.method('org.freedesktop.PolicyKit1.Authority',in_signature='(sa{sv})ss',out_signature='',sender_keyword='sender')
 def RegisterAuthenticationAgent(self,subject,locale,path,sender=None):
  print('REGISTER',subject,path,flush=True)
  self.sender=sender; self.path=path
  schedule=[(200,self.begin,'first'),(400,self.begin,'second'),(600,self.cancel,'first'),(800,self.cancel,'second'),(1000,self.begin,'third'),(1200,self.begin,'invalid'),(1400,self.begin,'fourth'),(1600,self.cancel,'third'),(1800,self.cancel,'fourth'),(2000,self.begin,'fifth'),(2200,self.begin,'queued'),(2400,self.cancel,'queued'),(2600,self.cancel,'fifth'),(2800,self.begin,'invalid-only'),(3000,self.begin,'sixth'),(3200,self.cancel,'sixth'),(3400,self.begin,'seventh'),(3600,self.begin,'invalid-tail'),(3800,self.cancel,'seventh'),(4000,self.begin,'eighth'),(4200,self.cancel,'eighth')]
  for ms,fn,name in schedule: GLib.timeout_add(ms,fn,name)
 @dbus.service.method('org.freedesktop.PolicyKit1.Authority',in_signature='(sa{sv})s',out_signature='')
 def UnregisterAuthenticationAgent(self,subject,path): pass
 @dbus.service.method('org.freedesktop.DBus.Properties',in_signature='s',out_signature='a{sv}')
 def GetAll(self,interface): return {}
 def ended(self,name,e):
  ended.add(name); print('ERROR',name,str(e),flush=True)
 def cancel(self,name):
  obj=bus.get_object(self.sender,self.path,introspect=False)
  obj.get_dbus_method('CancelAuthentication','org.freedesktop.PolicyKit1.AuthenticationAgent')('cookie-'+name,reply_handler=lambda:print('CANCEL SENT',name,flush=True),error_handler=lambda e:print('CANCEL ERROR',name,str(e),flush=True),signature='s')
  return False
 def begin(self,name):
  obj=bus.get_object(self.sender,self.path,introspect=False)
  method=obj.get_dbus_method('BeginAuthentication','org.freedesktop.PolicyKit1.AuthenticationAgent')
  identities=dbus.Array([dbus.Struct(('unix-user',dbus.Dictionary({'uid':dbus.UInt32(os.getuid())},signature='sv')),signature='sa{sv}')],signature='(sa{sv})')
  if name.startswith('invalid'):
   identities=dbus.Array([dbus.Struct(('unix-netgroup',dbus.Dictionary({'name':dbus.String('review')},signature='sv')),signature='sa{sv}')],signature='(sa{sv})')
  method('review.'+name,'Isolated mock','',{}, 'cookie-'+name, identities, reply_handler=lambda:print('DONE',name,flush=True),error_handler=lambda e:self.ended(name,e),signature='sssa{ss}sa(sa{sv})')
  return False
ended=set()
agent=Authority()
env=os.environ.copy(); env.update(DBUS_SYSTEM_BUS_ADDRESS=env['DBUS_SESSION_BUS_ADDRESS'],QT_QPA_PLATFORM='offscreen',LD_PRELOAD=str(ARTIFACTS / 'mock.so'))
p=subprocess.Popen([sys.argv[1] if len(sys.argv)>1 else 'quickshell','--no-color','-p',str(ARTIFACTS / 'backend-shell.qml')],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
GLib.timeout_add(5000,lambda:loop.quit())
try: loop.run()
finally:
 p.terminate(); p.wait(timeout=3)

output=p.stdout.read(); print(output)
expected={'first','second','third','invalid','fourth','fifth','queued','invalid-only','sixth','seventh','invalid-tail','eighth'}
assert ended==expected, f'Unresolved requests: {expected-ended}'
flows=[line.split('FLOW ',1)[1] for line in output.splitlines() if 'FLOW ' in line]
assert flows==['review.first','review.second','none','review.third','review.fourth','none','review.fifth','none','review.sixth','none','review.seventh','none','review.eighth','none'], flows
assert 'not found in the queue' not in output
print('PASS: serial activation, active/queued cancel, unsupported identity drain and idle recovery')
