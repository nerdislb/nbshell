#!/usr/bin/env python3
"""Lock the graphical session before logind suspends it.

The daemon owns a logind delay-inhibitor file descriptor. When logind emits
PrepareForSleep(true), it starts the isolated native locker and releases the
inhibitor only after the compositor-confirmed readiness marker appears, or
when the bounded delay budget expires. Lid, power-key, and direct system sleep
therefore share the same lock boundary.
"""

from __future__ import annotations

import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
from typing import Callable


READY_PATH = Path(os.environ.get("NBSHELL_LOCK_READY", f"/run/user/{os.getuid()}/nbshell-lock-ready"))
LOCK_UNIT = "nbshell-lock.service"
LOCK_TIMEOUT_SECONDS = 4.5
OUTPUT_WAIT_SECONDS = 8.0


def run_systemctl(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "--user", *arguments],
        capture_output=True,
        text=True,
        timeout=4,
        check=False,
        close_fds=True,
    )


def locker_active() -> bool:
    return run_systemctl("is-active", "--quiet", LOCK_UNIT).returncode == 0


def ensure_secure_lock(
    ready_path: Path = READY_PATH,
    timeout: float = LOCK_TIMEOUT_SECONDS,
    monotonic: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> bool:
    """Start the dedicated locker and wait for compositor-confirmed coverage."""
    active = locker_active()
    if active and ready_path.is_file():
        return True
    if not active:
        run_systemctl("reset-failed", LOCK_UNIT)
        started = run_systemctl("start", LOCK_UNIT)
        if started.returncode != 0:
            detail = started.stderr.strip() or started.stdout.strip() or "unknown error"
            print(f"nbshell: could not start sleep locker: {detail}", flush=True)
            return False

    deadline = monotonic() + timeout
    while monotonic() < deadline:
        if ready_path.is_file() and locker_active():
            return True
        if not locker_active():
            print("nbshell: sleep locker exited before becoming secure", flush=True)
            return False
        sleep(0.05)
    print("nbshell: sleep locker did not become secure before the inhibitor deadline", flush=True)
    return False


def umbriel_binary() -> str | None:
    system_binary = Path("/usr/local/bin/umbriel")
    if system_binary.is_file() and os.access(system_binary, os.X_OK):
        return str(system_binary)
    return shutil.which("umbriel")


def wake_outputs(
    binary: str | None = None,
    timeout: float = OUTPUT_WAIT_SECONDS,
    monotonic: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> bool:
    """Wake DPMS once Umbriel has recreated at least one real output."""
    binary = binary or umbriel_binary()
    if not binary:
        return False
    deadline = monotonic() + timeout
    while monotonic() < deadline:
        try:
            outputs = subprocess.run(
                [binary, "outputs"], capture_output=True, text=True,
                timeout=1, check=False, close_fds=True,
            )
            if outputs.returncode == 0 and outputs.stdout.strip():
                wake = subprocess.run(
                    [binary, "msg", "dpms-on"], capture_output=True, text=True,
                    timeout=1, check=False, close_fds=True,
                )
                if wake.returncode == 0:
                    print("nbshell: woke Umbriel outputs after resume", flush=True)
                    return True
        except (OSError, subprocess.TimeoutExpired):
            pass
        sleep(0.25)
    print("nbshell: no Umbriel output returned during the resume wake window", flush=True)
    return False


class SleepLockController:
    """Small state machine kept independent from D-Bus for deterministic tests."""

    def __init__(
        self,
        acquire_inhibitor: Callable[[], int],
        lock: Callable[[], bool] = ensure_secure_lock,
        wake: Callable[[], bool] = wake_outputs,
    ) -> None:
        self.acquire_inhibitor = acquire_inhibitor
        self.lock = lock
        self.wake = wake
        self.inhibitor_fd: int | None = None

    def acquire(self) -> None:
        self.release()
        descriptor = self.acquire_inhibitor()
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFD)
        fcntl.fcntl(descriptor, fcntl.F_SETFD, flags | fcntl.FD_CLOEXEC)
        self.inhibitor_fd = descriptor
        print("nbshell: acquired logind sleep delay inhibitor", flush=True)

    def release(self) -> None:
        if self.inhibitor_fd is not None:
            os.close(self.inhibitor_fd)
            self.inhibitor_fd = None

    def prepare_for_sleep(self, sleeping: bool) -> None:
        if sleeping:
            secured = False
            try:
                secured = self.lock()
            finally:
                self.release()
            state = "secure" if secured else "not confirmed secure"
            print(f"nbshell: releasing sleep inhibitor; locker is {state}", flush=True)
            return
        self.acquire()
        threading.Thread(target=self.wake, name="nbshell-resume-wake", daemon=True).start()


def main() -> int:
    try:
        import dbus
        from dbus.mainloop.glib import DBusGMainLoop
        from gi.repository import GLib  # type: ignore[attr-defined]
    except ImportError as error:
        print(f"nbshell: sleep lock inhibitor requires python-dbus and python-gobject: {error}", flush=True)
        return 1

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    manager_object = bus.get_object("org.freedesktop.login1", "/org/freedesktop/login1")
    manager = dbus.Interface(manager_object, "org.freedesktop.login1.Manager")

    def acquire_inhibitor() -> int:
        deadline = time.monotonic() + OUTPUT_WAIT_SECONDS
        while True:
            try:
                descriptor = manager.Inhibit(
                    "sleep", "nbshell", "Lock the graphical session before sleep", "delay"
                )
                return descriptor.take()
            except dbus.exceptions.DBusException as error:
                if error.get_dbus_name() != "org.freedesktop.login1.OperationInProgress":
                    raise
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.25)

    controller = SleepLockController(acquire_inhibitor)
    controller.acquire()
    main_loop = GLib.MainLoop()
    failed = False

    def on_prepare_for_sleep(sleeping: object) -> None:
        nonlocal failed
        try:
            controller.prepare_for_sleep(bool(sleeping))
        except Exception as error:
            failed = True
            print(f"nbshell: sleep inhibitor state transition failed: {error}", flush=True)
            main_loop.quit()

    bus.add_signal_receiver(
        on_prepare_for_sleep,
        signal_name="PrepareForSleep",
        dbus_interface="org.freedesktop.login1.Manager",
        bus_name="org.freedesktop.login1",
        path="/org/freedesktop/login1",
    )
    try:
        main_loop.run()
    finally:
        controller.release()
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
