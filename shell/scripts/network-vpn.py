#!/usr/bin/env python3
"""List and toggle NetworkManager VPN profiles without exposing secrets."""

import json
import re
import shutil
import subprocess
import sys


UUID = re.compile(r"^[0-9a-fA-F-]{36}$")
VPN_TYPES = {"vpn", "wireguard"}


def result(payload, code=0):
    print(json.dumps(payload, ensure_ascii=False))
    return code


def run(*args):
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=35)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def split_terse(line):
    fields = []
    field = []
    escaped = False
    for char in line:
        if escaped:
            field.append(char)
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            fields.append("".join(field))
            field = []
        else:
            field.append(char)
    if escaped:
        field.append("\\")
    fields.append("".join(field))
    return fields


def list_profiles():
    if not shutil.which("nmcli"):
        return result({"available": False, "profiles": [], "error": "NetworkManager is not installed"}, 1)

    code, output, error = run(
        "nmcli", "--terse", "--escape", "yes",
        "--fields", "UUID,TYPE,NAME", "connection", "show",
    )
    if code != 0:
        return result({"available": True, "profiles": [], "error": error or "Could not read VPN profiles"}, code)

    active_code, active_output, _ = run(
        "nmcli", "--terse", "--escape", "yes",
        "--fields", "UUID", "connection", "show", "--active",
    )
    active = set(active_output.splitlines()) if active_code == 0 else set()
    profiles = []
    for line in output.splitlines():
        fields = split_terse(line)
        if len(fields) != 3 or fields[1] not in VPN_TYPES:
            continue
        profiles.append({
            "uuid": fields[0],
            "type": fields[1],
            "name": fields[2],
            "active": fields[0] in active,
        })
    profiles.sort(key=lambda item: (not item["active"], item["name"].casefold()))
    return result({"available": True, "profiles": profiles, "error": ""})


def toggle(action, uuid):
    if not UUID.fullmatch(uuid):
        return result({"ok": False, "error": "Invalid VPN profile identifier"}, 2)
    verb = "up" if action == "up" else "down"
    code, output, error = run("nmcli", "--wait", "30", "connection", verb, "uuid", uuid)
    message = error or output
    if code != 0 and "Secrets were required" in message:
        message = "This VPN needs credentials. Save them in NetworkManager first, then try again."
    return result({"ok": code == 0, "error": "" if code == 0 else (message or "VPN action failed")}, code)


def main():
    if len(sys.argv) == 1 or sys.argv[1] == "list":
        return list_profiles()
    if len(sys.argv) == 3 and sys.argv[1] in {"up", "down"}:
        return toggle(sys.argv[1], sys.argv[2])
    return result({"ok": False, "error": "Usage: network-vpn.py [list|up UUID|down UUID]"}, 2)


if __name__ == "__main__":
    raise SystemExit(main())
