#!/usr/bin/env python3
"""Explicit, local OpenClaw setup. Never import another agent's credentials."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import sys
import tempfile

VERSION = '2026.9.4'
MODEL = 'openai/gpt-6-astra'
INSTALLER = 'https://openclaw.ai/install-cli.sh'
INSTALLER_SHA256 = '80f5784c7b70ef26314febee565a1041d39965c919132bb197ba6061cf738495'


def locations():
    home = Path.home()
    data = Path(os.getenv('XDG_DATA_HOME', home / '.local/share'))
    state = Path(os.getenv('XDG_STATE_HOME', home / '.local/state')) / 'nbshell/openclaw-setup'
    return home, data, state, home / '.openclaw/openclaw.json'


def executable():
    local = locations()[1] / 'openclaw/bin/openclaw'
    return str(local) if os.access(local, os.X_OK) else shutil.which('openclaw')


def run(*args, env=None):
    subprocess.run(list(args), env=env, check=True)


def environment():
    # Allow only desktop/session plumbing, never provider keys, endpoint overrides,
    # another agent's home, npm credentials or installer-control environment vars.
    allowed = {'HOME', 'USER', 'LOGNAME', 'PATH', 'LANG', 'TERM', 'COLORTERM',
               'DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'DBUS_SESSION_BUS_ADDRESS',
               'XDG_RUNTIME_DIR', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME',
               'XDG_SESSION_TYPE', 'TMPDIR', 'SSL_CERT_FILE', 'SSL_CERT_DIR'}
    env = {k: v for k, v in os.environ.items() if k in allowed or k.startswith('LC_')}
    prefix = locations()[1] / 'openclaw'
    env.update(npm_config_cache=str(prefix / 'cache/npm'),
               npm_config_userconfig=str(prefix / 'npmrc'))
    return env


def check_gateway_slot():
    result = subprocess.run(['systemctl', '--user', 'show', 'openclaw-gateway.service',
                             '--property=LoadState', '--value'], capture_output=True, text=True, check=True)
    if result.stdout.strip() != 'not-found':
        raise RuntimeError('An OpenClaw Gateway unit already exists. It will not be replaced by fresh setup.')
    with socket.socket() as sock:
        try:
            sock.bind(('127.0.0.1', 18789))
        except OSError:
            raise RuntimeError('Port 18789 is in use. Existing services are left untouched.')


def fresh_setup(claw, env):
    home, _, _, config = locations()
    run(claw, 'onboard', '--classic', '--flow', 'quickstart', '--mode', 'local',
        '--auth-choice', 'openai-device-code', '--gateway-bind', 'loopback',
        '--gateway-auth', 'token', '--gateway-port', '18789', '--tailscale', 'off',
        '--workspace', str(home / '.openclaw/workspace'), '--no-install-daemon',
        '--skip-channels', '--skip-search', '--skip-skills', '--skip-hooks', '--skip-ui', env=env)
    if not config.is_file():
        raise RuntimeError('Onboarding did not create a configuration. No service was installed.')
    cfg = json.loads(config.read_text())
    profiles = list(cfg.get('auth', {}).get('profiles', {}).values())
    if not profiles or any(p.get('provider') != 'openai' or p.get('mode') != 'oauth' for p in profiles):
        raise RuntimeError('Expected OpenAI subscription OAuth only. No service was installed; inspect setup with openclaw configure.')
    run(claw, 'models', 'set', MODEL, env=env)
    run(claw, 'models', 'fallbacks', 'clear', env=env)
    run(claw, 'config', 'validate', env=env)
    check_gateway_slot()
    run(claw, 'gateway', 'install', '--runtime', 'node', env=env)
    run(claw, 'gateway', 'status', env=env)
    run(claw, 'gateway', 'health', env=env)


def install():
    home, data, state, config = locations()
    for key in ('OPENCLAW_HOME', 'OPENCLAW_STATE_DIR', 'OPENCLAW_CONFIG_PATH', 'OPENCLAW_PROFILE'):
        if os.environ.get(key):
            raise RuntimeError(f'{key} selects a custom installation. Use its own OpenClaw CLI; this shortcut leaves it unchanged.')
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'install.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('OpenClaw setup is already running.')
        claw = executable()
        if config.exists():
            if (state / 'pending-setup').exists():
                raise RuntimeError('Previous setup is incomplete. Finish with the installed CLI: configure, gateway install, gateway health. See docs/openclaw-setup.md; existing configuration is preserved.')
            if not claw:
                raise RuntimeError('Existing OpenClaw configuration found, but CLI is missing. Restore its CLI without resetting the configuration.')
            print('Existing OpenClaw configuration preserved. Opening its dashboard.', flush=True)
            run(claw, 'config', 'validate', env=environment())
            run(claw, 'dashboard', env=environment())
            return
        if config.parent.exists() and any(config.parent.iterdir()):
            raise RuntimeError('Existing OpenClaw state without configuration found. Use its CLI to recover; this shortcut will not adopt credentials or overwrite workspace data.')
        if not sys.stdin.isatty():
            raise RuntimeError('Run setup from a terminal so OpenClaw can ask for sign-in and onboarding consent.')
        if os.geteuid() == 0 or platform.system() != 'Linux' or platform.libc_ver()[0] != 'glibc':
            raise RuntimeError('This shortcut requires a regular user on glibc Linux.')
        for dep in ('bash', 'curl', 'git', 'tar', 'xz', 'systemctl'):
            if not shutil.which(dep):
                raise RuntimeError(f'Install {dep} with your package manager first. No system packages are installed by nbshell.')
        subprocess.run(['systemctl', '--user', 'show-environment'], check=True, stdout=subprocess.DEVNULL)
        check_gateway_slot()
        env = environment()
        private_cli = data / 'openclaw/bin/openclaw'
        claw = str(private_cli) if os.access(private_cli, os.X_OK) else None
        if not claw:
            print('Installing OpenClaw and its private Node runtime. System Node and other agents stay unchanged.', flush=True)
            with tempfile.TemporaryDirectory(prefix='nbshell-openclaw-') as temp:
                script = Path(temp) / 'install-cli.sh'
                run('curl', '--fail', '--show-error', '--silent', '--location', '--proto', '=https',
                    '--tlsv1.2', '--connect-timeout', '20', '--max-time', '120',
                    INSTALLER, '--output', str(script), env=env)
                if hashlib.sha256(script.read_bytes()).hexdigest() != INSTALLER_SHA256:
                    raise RuntimeError('The official installer changed. Update nbshell to a reviewed installer revision before retrying; downloaded script was not executed.')
                run('bash', str(script), '--prefix', str(data / 'openclaw'), '--version', VERSION,
                    '--install-method', 'npm', '--no-onboard', env=env)
            claw = str(private_cli)
            if not os.access(private_cli, os.X_OK):
                raise RuntimeError('Installer finished without a usable OpenClaw CLI.')
        print('Complete the OpenAI subscription sign-in. No API key or paid fallback is configured.', flush=True)
        pending = state / 'pending-setup'
        pending.write_text('Initial onboarding/service setup has not completed.\n')
        fresh_setup(claw, env)
        pending.unlink()
        # An app shortcut invokes the public nbshell route, not a tokenized URL.
        apps = data / 'applications'
        apps.mkdir(parents=True, exist_ok=True)
        desktop = apps / 'nbshell-openclaw.desktop'
        if not desktop.exists():
            desktop.write_text('[Desktop Entry]\nType=Application\nName=OpenClaw\n'
                               'Comment=Open your local AI workspace\nExec=nbshell openclaw open\n'
                               'Icon=applications-internet\nTerminal=false\nCategories=Utility;\n')
        if shutil.which('update-desktop-database'):
            subprocess.run(['update-desktop-database', str(apps)], check=False)
        run(claw, 'dashboard', env=env)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'install'
    os.umask(0o077)
    if action == 'install':
        install()
    elif action == 'open':
        if any(os.environ.get(key) for key in ('OPENCLAW_HOME', 'OPENCLAW_STATE_DIR', 'OPENCLAW_CONFIG_PATH', 'OPENCLAW_PROFILE')):
            raise RuntimeError('Use the custom installation\'s own OpenClaw CLI to open its dashboard.')
        claw = executable()
        if not claw:
            raise RuntimeError('Install OpenClaw from the nbshell menu first.')
        run(claw, 'dashboard', env=environment())
    elif action == 'status':
        print(json.dumps({'installed': bool(executable()), 'configured': locations()[3].is_file(),
                          'setupVersion': VERSION, 'setupModel': MODEL}))
    else:
        raise RuntimeError('Usage: nbshell openclaw install|open|status')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'OpenClaw setup stopped: {exc}', file=sys.stderr)
        sys.exit(1)
