#!/usr/bin/env python3
"""Read-only, allowlisted diagnostics suitable for sharing (no local system map)."""
from __future__ import annotations

import argparse
import json
import os
import selectors
import signal
import time
from pathlib import Path
import re
import subprocess
import sys

SCRIPTS = Path(__file__).resolve().parent
TIMEOUT = 3
UNITS = ("nbshell.service", "nbshell-umbriel-resume-guard.service",
         "xdg-desktop-portal.service", "xdg-desktop-portal-umbriel.service",
         "pipewire.service", "wireplumber.service")
STATES = {"active", "reloading", "inactive", "failed", "activating", "deactivating", "maintenance", "refreshing"}


def probe(command, timeout=TIMEOUT):
    """Discard stderr entirely; only callers' allowlisted values reach the report."""
    try:
        with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, close_fds=True,
                              start_new_session=True) as process:
            try:
                assert process.stdout is not None
                deadline = time.monotonic() + timeout
                data = bytearray()
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    while True:
                        remaining = deadline - time.monotonic()
                        if remaining <= 0 or not selector.select(remaining):
                            return "timeout", ""
                        chunk = os.read(process.stdout.fileno(), min(4096, 65537 - len(data)))
                        if not chunk:
                            break
                        data.extend(chunk)
                        if len(data) > 65536:
                            return "invalid", ""
                code = process.wait(timeout=max(0.001, deadline - time.monotonic()))
                return ("ok", data.decode("utf-8", errors="replace").strip()) if code == 0 else ("failed", "")
            finally:
                # Kill hung descendants too, including a child keeping stdout open.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    except FileNotFoundError:
        return "missing-tool", ""
    except subprocess.TimeoutExpired:
        return "timeout", ""
    except OSError:
        return "unavailable", ""


def json_probe(command, timeout=TIMEOUT):
    state, text = probe(command, timeout)
    if state != "ok":
        return state, {}
    try:
        value = json.loads(text)
    except (ValueError, RecursionError):
        return "invalid", {}
    return ("ok", value) if isinstance(value, dict) else ("invalid", {})


def enum(value, allowed, fallback="unknown"):
    return value if isinstance(value, str) and value in allowed else fallback


def compositor_status():
    state, value = json_probe([sys.executable, str(SCRIPTS / "umbriel-contract.py"), "status", "--json"], 12)
    runtime = value.get("runtime")
    runtime = runtime if isinstance(runtime, dict) else {}
    rows = value.get("capabilities")
    valid = (state == "ok" and value.get("schemaVersion") == 1 and
             isinstance(rows, list) and bool(rows) and all(
                 isinstance(row, dict) and type(row.get("required")) is bool and
                 type(row.get("available")) is bool for row in rows))
    required = sum(row["required"] and not row["available"] for row in (rows or [])) if valid else None
    optional = sum(not row["required"] and not row["available"] for row in (rows or [])) if valid else None
    connected = runtime.get("socketAvailable") is True if valid else False
    # Runtime availability is deliberately independent of tested revision support.
    health = "healthy" if valid and connected and required == 0 else "unhealthy" if valid else "unknown"
    return {"health": health, "probe": state if valid or state != "ok" else "invalid",
            "socketAvailable": connected, "missingRequiredCount": required,
            "missingOptionalCount": optional,
            "capabilityScope": "binary-advertisement-and-socket-connectivity"}


def stack_status():
    # A missing/changed evaluator must never turn into a supported-stack assertion.
    state, value = json_probe([sys.executable, str(SCRIPTS / "stack-status.py"), "--json"], 20)
    return sanitize_stack(state, value)


def sanitize_stack(state, value):
    """Projection only: never pass arbitrary evaluator text or paths through."""
    states = {"tested", "supported", "compatible-unverified", "degraded", "unsupported", "security-blocked"}
    names = ("nbshell", "quickshell", "qt", "umbriel", "portal", "platform")
    reasons = {"security-policy", "known-incompatible", "below-minimum", "non-linux-platform",
               "missing-component", "functional-check-failed", "unknown-or-unresolved-version",
               "development-build", "documented-baseline", "outside-recorded-baseline", "exact-tested-stack"}
    unknown = {"status": "unknown", "probe": state if state != "ok" else "invalid", "components": {}}
    components = value.get("components")
    if (state != "ok" or type(value.get("schemaVersion")) is not int or value["schemaVersion"] != 1
            or enum(value.get("status"), states) == "unknown" or not isinstance(components, dict)
            or set(components) != set(names)):
        return unknown
    projected = {}
    for name in names:
        row = components[name]
        if (not isinstance(row, dict) or enum(row.get("status"), states) == "unknown"
                or enum(row.get("reason"), reasons) == "unknown"
                or type(row.get("dirty")) is not bool
                or (row.get("available") is not None and type(row.get("available")) is not bool)):
            return unknown
        raw = row.get("value")
        # Restrict version suffixes: arbitrary build metadata can encode host/user names.
        pattern = (r"[0-9a-f]{40}" if name in {"umbriel", "portal"} else
                   r"linux:(?:arch|endeavouros|manjaro|debian|ubuntu|fedora|opensuse)" if name == "platform" else
                   r"[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}(?:-(?:alpha|beta|rc)\.[0-9]{1,6})?")
        safe = raw if isinstance(raw, str) and re.fullmatch(pattern, raw) else None
        projected[name] = {"value": safe, "status": row["status"], "reason": row["reason"],
                           "available": row.get("available"), "dirty": row["dirty"]}
    # Do not accept an inconsistent aggregate that suppresses a component failure.
    order = ("tested", "supported", "compatible-unverified", "degraded", "unsupported", "security-blocked")
    if value["status"] != max((row["status"] for row in projected.values()), key=order.index):
        return unknown
    return {"status": value["status"], "probe": "ok", "components": projected}


def portal_status():
    checks = {}
    for key, interface, prop in (
        ("screenshot", "Screenshot", "version"),
        ("screenCast", "ScreenCast", "version"),
        ("sourceTypes", "ScreenCast", "AvailableSourceTypes"),
    ):
        state, text = probe(["busctl", "--user", "--auto-start=no", "--timeout=3", "get-property",
                             "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                             "org.freedesktop.portal." + interface, prop])
        match = re.fullmatch(r"u ([0-9]{1,10})", text) if state == "ok" else None
        number = int(match[1]) if match and int(match[1]) <= 4294967295 else None
        checks[key] = {"probe": state if state != "ok" else "ok" if number is not None else "invalid",
                       "available": number is not None and number > 0}
    available = all(item["available"] for item in checks.values())
    unknown = any(item["probe"] in {"missing-tool", "invalid", "timeout", "unavailable"} for item in checks.values())
    return {"health": "healthy" if available else "unknown" if unknown else "unhealthy",
            "checks": checks, "scope": "read-only-dbus-properties-no-activation",
            "consentCaptureTested": False}


def service_status(name):
    state, text = probe(["systemctl", "--user", "--no-pager", "show", "--property=ActiveState", "--value", name])
    return {"unit": name, "state": enum(text, STATES) if state == "ok" else "unknown",
            "probe": state if state != "ok" else "ok" if text in STATES else "invalid"}


def collect():
    stack = stack_status()
    compositor = compositor_status()
    portal = portal_status()
    services = [service_status(name) for name in UNITS]
    shell = services[0]["state"]
    shell_health = "healthy" if shell == "active" else "unknown" if shell == "unknown" else "unhealthy"
    core = (compositor["health"], shell_health)
    health = "unhealthy" if "unhealthy" in core else "unknown" if "unknown" in core else "healthy"
    advice = []
    if stack["status"] not in {"tested", "supported"}:
        advice.append("Check the tested stack documentation before updating components.")
    if compositor["health"] != "healthy":
        advice.append("Run nbshell compositor status inside the Umbriel session.")
    if shell_health != "healthy":
        advice.append("Run nbshell status and inspect nbshell log locally.")
    if portal["health"] != "healthy":
        advice.append("Inspect systemctl --user status xdg-desktop-portal.service xdg-desktop-portal-umbriel.service locally.")
    return {"schemaVersion": 1, "reportType": "nbshell-support", "shareable": True,
            "support": stack, "runtime": {"health": health, "shell": shell_health,
            "compositor": compositor, "portal": portal}, "services": services,
            "remediation": advice}


def healthy(data):
    return (data["support"]["status"] in {"tested", "supported"} and data["runtime"]["health"] == "healthy"
            and data["runtime"]["portal"]["health"] == "healthy")


def human(data):
    rows = ["nbshell doctor (shareable)", "Stack support: " + data["support"]["status"],
            "Core runtime: " + data["runtime"]["health"],
            "Portal readiness: " + data["runtime"]["portal"]["health"],
            "Portal check reads D-Bus properties only; user-consent capture was not exercised."]
    rows.extend(item["unit"] + ": " + item["state"] for item in data["services"])
    rows.extend("- " + item for item in data["remediation"])
    return "\n".join(rows)


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print deterministic shareable JSON")
    parser.add_argument("--check", action="store_true", help="exit 1 unless stack, core runtime and portal readiness are verified")
    args = parser.parse_args(arguments)
    data = collect()
    print(json.dumps(data, sort_keys=True, separators=(",", ":")) if args.json else human(data))
    return 1 if args.check and not healthy(data) else 0


if __name__ == "__main__":
    raise SystemExit(main())
