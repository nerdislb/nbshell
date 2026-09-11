#!/usr/bin/env python3
"""Require a visible Orbital surface on private headless Wayland outputs.

Preview only: no host Wayland, greetd socket, session bus or input devices.
Failure (including missing test dependencies) blocks greeter deployment.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def graphics_devices(render_node, sys_class=Path('/sys/class/drm'),
                     nvidia_gpus=Path('/proc/driver/nvidia/gpus'), dev=Path('/dev')):
    """Expose the selected render device and its NVIDIA EGL dependencies only."""
    devices = [render_node]
    pci_device = (sys_class / render_node.name / 'device').resolve(strict=True)
    vendor = pci_device / 'vendor'
    if not vendor.exists() or vendor.read_text().strip().lower() != '0x10de':
        return devices
    if (pci_device / 'driver').resolve().name != 'nvidia':
        return devices
    information = (nvidia_gpus / pci_device.name / 'information').read_text()
    minor = re.search(r'^Device Minor:\s*([0-9]+)\s*$', information, re.MULTILINE)
    if not minor:
        raise RuntimeError('Cannot identify the selected NVIDIA graphics device')
    for device in (dev / 'nvidiactl', dev / ('nvidia' + minor.group(1))):
        if not device.is_char_device():
            raise RuntimeError('Missing NVIDIA graphics device: ' + str(device))
        devices.append(device)
    return devices


def inside():
    Path('/run/test').mkdir(mode=0o700)
    Path('/home/test').mkdir()
    os.environ.update(
        HOME='/home/test', XDG_RUNTIME_DIR='/run/test',
        WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='2',
        WLR_LIBINPUT_NO_DEVICES='1', QT_QPA_PLATFORM='wayland',
        QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
        NBSHELL_GREETER_PREVIEW='1', NBSHELL_GREETER_CONFIG='/payload/config.json',
    )
    Path('/work/umbriel.toml').write_text(
        '[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n')
    processes = []
    try:
        with open('/work/compositor.log', 'w') as log:
            compositor = subprocess.Popen(
                ['/usr/local/bin/umbriel', '-c', '/work/umbriel.toml'],
                stdout=log, stderr=subprocess.STDOUT)
        processes.append(compositor)
        deadline = time.monotonic() + 10
        while not Path('/run/test/wayland-0').is_socket():
            if compositor.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('Private compositor did not start')
            time.sleep(.05)
        os.environ.update(WAYLAND_DISPLAY='wayland-0',
                          UMBRIEL_SOCKET='/run/test/umbriel-wayland-0.sock')
        with open('/work/quickshell.log', 'w') as log:
            frontend = subprocess.Popen(['/usr/bin/quickshell', '-p', '/payload', '--no-color'],
                                        stdout=log, stderr=subprocess.STDOUT)
        processes.append(frontend)
        deadline = time.monotonic() + 10
        stable_since = None
        while time.monotonic() < deadline:
            if any(proc.poll() is not None for proc in processes):
                raise RuntimeError('Greeter or compositor exited before readiness')
            log = Path('/work/quickshell.log').read_text()
            if any(message in log for message in (
                    'Required property', 'failed to create variant', 'Failed to load configuration')):
                raise RuntimeError('Greeter component creation failed')
            result = subprocess.run(['/usr/local/bin/umbriel', 'layers', '--json'],
                                    capture_output=True, text=True, timeout=2)
            layers = json.loads(result.stdout) if result.returncode == 0 else []
            outputs = {layer.get('output') for layer in layers
                       if layer.get('mapped') and layer.get('namespace') == 'nbshell:orbital-greeter'}
            if outputs == {'HEADLESS-1', 'HEADLESS-2'}:
                stable_since = stable_since or time.monotonic()
                if time.monotonic() - stable_since >= .5:
                    print('Greeter check: mapped Orbital surfaces on two isolated outputs.')
                    return
            else:
                stable_since = None
            time.sleep(.05)
        raise RuntimeError('Greeter never mapped both output surfaces')
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        inside()
        return
    bundle = args.bundle.resolve(strict=True)
    for name in ('shell.qml', 'GreeterView.qml', 'OrbitalClock.qml', 'ClockMath.js', 'qmldir', 'config.json'):
        if not (bundle / name).is_file():
            raise RuntimeError('Missing bundle file: ' + name)
    for binary in ('bwrap', 'dbus-run-session', '/usr/local/bin/umbriel', '/usr/bin/quickshell'):
        if not shutil.which(binary):
            raise RuntimeError('Missing greeter validation dependency: ' + binary)
    render_nodes = sorted(Path('/dev/dri').glob('renderD*'))
    if not render_nodes:
        raise RuntimeError('No DRM render node available for isolated greeter validation')
    device_bindings = []
    for device in graphics_devices(render_nodes[0]):
        device_bindings.extend(['--dev-bind', str(device), str(device)])
    with tempfile.TemporaryDirectory(prefix='nbshell-greeter-check-') as directory:
        command = [
            'bwrap', '--unshare-all', '--die-with-parent', '--new-session', '--cap-drop', 'ALL',
            '--ro-bind', '/usr', '/usr', '--symlink', 'usr/bin', '/bin',
            '--symlink', 'usr/lib', '/lib', '--symlink', 'usr/lib', '/lib64',
            '--ro-bind', '/etc', '/etc', '--ro-bind', '/sys', '/sys',
            '--proc', '/proc', '--dev', '/dev',
            *device_bindings,
            '--tmpfs', '/tmp', '--tmpfs', '/run', '--tmpfs', '/home',
            '--ro-bind', str(bundle), '/payload', '--bind', directory, '/work',
            '--ro-bind', str(Path(__file__).resolve()), '/check.py',
            '--clearenv', '--setenv', 'PATH', '/usr/local/bin:/usr/bin:/bin',
            '--setenv', 'LANG', 'C.UTF-8',
            '--setenv', 'WLR_RENDER_DRM_DEVICE', str(render_nodes[0]),
            '--chdir', '/work', '--', 'dbus-run-session', '--',
            'python3', '/check.py', '/payload', '--inside',
        ]
        try:
            result = subprocess.run(command, timeout=35)
            if result.returncode:
                raise RuntimeError('Isolated greeter validation failed; active bundle was not approved')
        except (RuntimeError, subprocess.TimeoutExpired):
            for name in ('compositor.log', 'quickshell.log'):
                log = Path(directory) / name
                if log.exists():
                    print(log.read_text()[-8000:], file=sys.stderr)
            raise


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
