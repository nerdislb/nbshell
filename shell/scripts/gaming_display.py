"""Private, authenticated X server for Windows installers; never touch the desktop."""
import ctypes as C
import os
from pathlib import Path
import secrets
import selectors
import struct
import subprocess
import tempfile


class Message(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', C.c_void_p), ('window', C.c_ulong), ('message_type', C.c_ulong),
                ('format', C.c_int), ('data', C.c_long * 5)]


class Event(C.Union):
    _fields_ = [('client', Message), ('padding', C.c_long * 24)]


class PrivateDisplay:
    def __init__(self, executable, log):
        self.executable, self.log = executable, log
        self.process = self.connection = self.folder = None

    def __enter__(self):
        self.folder = tempfile.TemporaryDirectory(prefix='nbshell-gaming-')
        auth = Path(self.folder.name) / 'Xauthority'
        fields = [b'', b'', b'MIT-MAGIC-COOKIE-1', secrets.token_bytes(16)]
        auth.write_bytes(struct.pack('>H', 65535) + b''.join(struct.pack('>H', len(v)) + v for v in fields))
        auth.chmod(0o600)
        r, w = os.pipe()
        try:
            self.process = subprocess.Popen([self.executable, '-displayfd', str(w), '-screen', '0',
                '1280x800x24', '-nolisten', 'tcp', '-auth', str(auth)], pass_fds=(w,),
                stdout=self.log, stderr=self.log)
            os.close(w)
            w = None
            with selectors.DefaultSelector() as selector:
                selector.register(r, selectors.EVENT_READ)
                if not selector.select(15):
                    raise RuntimeError('Private installer display did not start.')
            number = os.read(r, 40).decode().strip()
            if not number.isdigit():
                raise RuntimeError('Private installer display failed.')
            self.env = {'DISPLAY': ':' + number, 'XAUTHORITY': str(auth), 'PROTON_ENABLE_WAYLAND': '0'}
            # Xlib reads XAUTHORITY from this supervisor; children get explicit environments.
            prior = os.environ.get('XAUTHORITY')
            os.environ['XAUTHORITY'] = str(auth)
            try:
                self.x = C.CDLL('libX11.so.6')
                signatures = {
                    'XOpenDisplay': ([C.c_char_p], C.c_void_p),
                    'XDefaultRootWindow': ([C.c_void_p], C.c_ulong),
                    'XQueryTree': ([C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)], C.c_int),
                    'XFetchName': ([C.c_void_p, C.c_ulong, C.POINTER(C.c_char_p)], C.c_int),
                    'XInternAtom': ([C.c_void_p, C.c_char_p, C.c_int], C.c_ulong),
                    'XSendEvent': ([C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)], C.c_int),
                    'XFlush': ([C.c_void_p], C.c_int),
                    'XCloseDisplay': ([C.c_void_p], C.c_int),
                    'XFree': ([C.c_void_p], C.c_int),
                }
                for name, (args, result) in signatures.items():
                    fn = getattr(self.x, name)
                    fn.argtypes, fn.restype = args, result
                # Windows may disappear between enumeration and WM_DELETE_WINDOW.
                self.error_handler = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)(lambda *_: 0)
                self.x.XSetErrorHandler(self.error_handler)
                self.connection = self.x.XOpenDisplay(self.env['DISPLAY'].encode())
                if not self.connection:
                    raise RuntimeError('Cannot connect to private installer display.')
            finally:
                if prior is None:
                    os.environ.pop('XAUTHORITY', None)
                else:
                    os.environ['XAUTHORITY'] = prior
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise
        finally:
            os.close(r)
            if w is not None:
                os.close(w)

    def windows(self):
        root, parent, count = C.c_ulong(), C.c_ulong(), C.c_uint()
        children = C.POINTER(C.c_ulong)()
        x, d = self.x, self.connection
        result = []
        if x.XQueryTree(d, x.XDefaultRootWindow(d), C.byref(root), C.byref(parent), C.byref(children), C.byref(count)):
            for i in range(count.value):
                name = C.c_char_p()
                if x.XFetchName(d, children[i], C.byref(name)) and name.value:
                    result.append((children[i], name.value.decode(errors='replace')))
                    x.XFree(name)
            if children:
                x.XFree(children)
        return result

    def close(self, window):
        event = Event()
        event.client.type = 33  # ClientMessage
        event.client.display = self.connection
        event.client.window = window
        event.client.message_type = self.x.XInternAtom(self.connection, b'WM_PROTOCOLS', 0)
        event.client.format = 32
        event.client.data[0] = self.x.XInternAtom(self.connection, b'WM_DELETE_WINDOW', 0)
        self.x.XSendEvent(self.connection, window, 0, 0, C.byref(event))
        self.x.XFlush(self.connection)

    def __exit__(self, *_):
        if self.connection:
            self.x.XCloseDisplay(self.connection)
            self.connection = None
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        if self.folder:
            self.folder.cleanup()
