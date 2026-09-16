#!/usr/bin/env python3
"""Bounded speedtest-cli/Ookla adapter with cancellation of its entire child group."""
import json
import math
import os
import shutil
import signal
import subprocess


def normalized(data, ookla=False):
    def number(value, factor=1):
        value = float(0 if value is None else value) * factor
        if not math.isfinite(value) or value < 0:
            raise ValueError('Invalid measurement')
        return round(value, 1)
    server = data.get('server') or {}
    if ookla:
        ping = number((data.get('ping') or {}).get('latency'))
        down = number((data.get('download') or {}).get('bandwidth'), 8 / 1e6)
        up = number((data.get('upload') or {}).get('bandwidth'), 8 / 1e6)
        name = ', '.join(str(server[key]) for key in ('location', 'name') if server.get(key))
    else:
        ping = number(data.get('ping'))
        down = number(data.get('download'), 1 / 1e6)
        up = number(data.get('upload'), 1 / 1e6)
        name = ', '.join(str(server[key]) for key in ('name', 'sponsor') if server.get(key))
    return dict(ok=True, ping=ping, down=down, up=up, server=name or '?')


def measure(timeout=120):
    client = shutil.which('speedtest-cli')
    ookla = not client
    if not client:
        client = shutil.which('speedtest')
    if not client:
        return dict(ok=False, grund='Install speedtest-cli to measure your connection')
    command = [client, '--format=json', '--accept-license', '--accept-gdpr'] if ookla else [client, '--json']
    child = None
    pending_cancel = 0

    def stop():
        if child is None:
            return
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            child.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
        finally:
            # A worker may outlive the client leader or ignore TERM.
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()

    def cancel(signum, frame):
        nonlocal pending_cancel
        if child is None:
            pending_cancel = signum
            return
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        stop()
        raise SystemExit(128 + signum)

    old_handlers = {sig: signal.signal(sig, cancel) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        # Defer cancellation until Popen has returned ownership of the child.
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 text=True, start_new_session=True)
        if pending_cancel:
            cancel(pending_cancel, None)
        output, _ = child.communicate(timeout=timeout)
        if child.returncode:
            return dict(ok=False, grund='Speed test failed. Check your connection and try again')
        return normalized(json.loads(output), ookla)
    except subprocess.TimeoutExpired:
        return dict(ok=False, grund='Speed test timed out. Try again')
    except (OSError, ValueError, TypeError, AttributeError):
        return dict(ok=False, grund='Speed test returned an invalid response')
    finally:
        stop()
        if child is not None and child.stdout is not None:
            child.stdout.close()
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    print(json.dumps(measure(), ensure_ascii=False, allow_nan=False))
