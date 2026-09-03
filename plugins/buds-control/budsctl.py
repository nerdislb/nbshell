#!/usr/bin/env python3
"""JSON bridge for direct Pixel Buds control and the BudsLink fallback."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time
from typing import Any

SERVICE = "io.github.maniacx.BudsLink"
MANAGER_PATH = "/io/github/maniacx/BudsLink"
MANAGER_IFACE = "io.github.maniacx.BudsLink.DeviceManager"
DEVICE_IFACE = "io.github.maniacx.BudsLink.Device"
CLIENT_ID = "io.github.nerdislb.buds-control"
DEVICE_PATH = re.compile(r"^/io/github/maniacx/BudsLink/Devices/[A-Za-z0-9_]+/[A-Za-z0-9_]+$")
PIXEL_PATH = re.compile(r"^pixel:([0-9A-F]{2}(?::[0-9A-F]{2}){5})$")
CONNECTED_PIXEL = re.compile(
    r"^Device\s+([0-9A-F]{2}(?::[0-9A-F]{2}){5})\s+(.+Pixel Buds Pro(?: 2)?)$",
    re.IGNORECASE,
)
PBP_MODES = {
    1: ("Off", "off"),
    2: ("Transparency", "aware"),
    3: ("Noise Cancellation", "active"),
    4: ("Adaptive", "adaptive"),
}


def run_text(command: list[str], timeout: int = 10) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)
    return result.stdout.strip()


def busctl(*arguments: str, json_output: bool = False) -> Any:
    command = ["busctl", "--user"]
    if json_output:
        command.append("--json=short")
    command.extend(arguments)
    output = run_text(command, timeout=8)
    return json.loads(output) if json_output else None


def call(method: str, *signature_and_arguments: str, json_output: bool = False) -> Any:
    return busctl(
        "call", SERVICE, MANAGER_PATH, MANAGER_IFACE, method,
        *signature_and_arguments, json_output=json_output,
    )


def property_value(path: str, name: str) -> Any:
    reply = busctl(
        "get-property", SERVICE, path, DEVICE_IFACE, name,
        json_output=True,
    )
    return reply.get("data")


def start_and_hold() -> str:
    version_reply = call("ServiceVersion", json_output=True)
    call("HoldService", "s", CLIENT_ID)
    data = version_reply.get("data", [])
    return str(data[0]) if isinstance(data, list) and data else "unknown"


def mode_options(config: dict[str, Any]) -> list[dict[str, Any]]:
    options: list[dict[str, Any]] = []
    for index in range(1, 5):
        label = str(config.get(f"toggle1Button{index}Name") or "").strip()
        if label:
            options.append({"label": label, "value": index})
    return options


def connected_pixel_buds() -> tuple[str, str] | None:
    if not shutil.which("pbpctrl") or not shutil.which("bluetoothctl"):
        return None
    output = run_text(["bluetoothctl", "devices", "Connected"], timeout=5)
    for line in output.splitlines():
        match = CONNECTED_PIXEL.fullmatch(line.strip())
        if match:
            return match.group(1).upper(), match.group(2)
    return None


def budslink_has_owner() -> bool:
    try:
        reply = busctl(
            "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "NameHasOwner", "s", SERVICE,
            json_output=True,
        )
        data = reply.get("data", [])
        return bool(data and data[0] is True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return False


def stop_flatpak_budslink() -> None:
    """Release BudsLink's competing Pixel RFCOMM registration when necessary."""
    if not budslink_has_owner() or not shutil.which("flatpak"):
        return
    subprocess.run(
        ["flatpak", "kill", SERVICE],
        capture_output=True, text=True, timeout=8, check=False,
    )
    for _ in range(10):
        if not budslink_has_owner():
            return
        time.sleep(0.1)


def pbp_mode_options() -> list[dict[str, Any]]:
    help_text = run_text(["pbpctrl", "set", "anc", "--help"], timeout=5)
    values_match = re.search(r"possible values:\s*([^\]]+)\]", help_text)
    supported = {
        value.strip()
        for value in values_match.group(1).split(",")
    } if values_match else {"off", "active", "aware"}
    return [
        {"label": label, "value": value}
        for value, (label, command) in PBP_MODES.items()
        if command in supported
    ]


def parse_pbp_battery(text: str) -> dict[str, tuple[int, str]]:
    batteries: dict[str, tuple[int, str]] = {}
    names = {"case": "battery3", "left bud": "battery1", "right bud": "battery2"}
    for line in text.splitlines():
        match = re.fullmatch(r"\s*(case|left bud|right bud):\s+(unknown|(\d{1,3})%\s+\(([^)]+)\))\s*", line)
        if not match:
            continue
        key = names[match.group(1)]
        if match.group(2) == "unknown":
            batteries[key] = (0, "not-reported")
            continue
        level = max(0, min(100, int(match.group(3))))
        detail = match.group(4).lower()
        status = "charging" if detail == "charging" else "discharging"
        batteries[key] = (level, status)
    return batteries


def read_pbp_status(address: str, alias: str) -> dict[str, Any]:
    stop_flatpak_budslink()
    mode_name = run_text(["pbpctrl", "-d", address, "get", "anc"]).lower()
    mode_by_name = {command: value for value, (_, command) in PBP_MODES.items()}
    if mode_name not in mode_by_name:
        raise RuntimeError(f"Unknown Pixel Buds noise-control state: {mode_name}")
    batteries = parse_pbp_battery(
        run_text(["pbpctrl", "-d", address, "show", "battery"])
    )
    if "battery1" not in batteries and "battery2" not in batteries:
        raise RuntimeError("Pixel Buds did not report battery data")
    levels = [level for level, status in batteries.values() if status != "not-reported"]
    state: dict[str, Any] = {
        "computedBatteryLevel": min(levels) if levels else 0,
        "toggle1State": mode_by_name[mode_name],
        "toggle1Visible": True,
    }
    for index in range(1, 4):
        level, status = batteries.get(f"battery{index}", (0, "not-reported"))
        state[f"battery{index}Level"] = level
        state[f"battery{index}Status"] = status
    return {
        "ok": True,
        "available": True,
        "backend": "pbpctrl",
        "version": run_text(["pbpctrl", "--version"], timeout=5).removeprefix("pbpctrl "),
        "devices": [{
            "path": f"pixel:{address}",
            "alias": alias,
            "config": {},
            "state": state,
            "modes": pbp_mode_options(),
        }],
    }


def read_budslink_status() -> dict[str, Any]:
    version = start_and_hold()
    paths: list[str] = []
    for attempt in range(5):
        reply = call("ListDevices", json_output=True)
        data = reply.get("data", [])
        paths = data[0] if isinstance(data, list) and data and isinstance(data[0], list) else []
        if paths or attempt == 4:
            break
        time.sleep(0.4)
    devices = []
    for path in paths:
        if not isinstance(path, str) or not DEVICE_PATH.fullmatch(path):
            continue
        config = json.loads(str(property_value(path, "Config") or "{}"))
        state = json.loads(str(property_value(path, "State") or "{}"))
        devices.append({
            "path": path,
            "alias": str(property_value(path, "Alias") or "Bluetooth earbuds"),
            "config": config,
            "state": state,
            "modes": mode_options(config),
        })
    return {
        "ok": True,
        "available": True,
        "backend": "budslink",
        "version": version,
        "devices": devices,
    }


def read_status() -> dict[str, Any]:
    pixel = connected_pixel_buds()
    if pixel:
        return read_pbp_status(*pixel)
    return read_budslink_status()


def set_pbp_mode(path: str, value: int) -> dict[str, Any]:
    match = PIXEL_PATH.fullmatch(path)
    if not match or value not in PBP_MODES:
        raise ValueError("Invalid Pixel Buds mode request")
    address = match.group(1)
    target = PBP_MODES[value][1]
    supported = {int(option["value"]) for option in pbp_mode_options()}
    if value not in supported:
        raise ValueError(f"{PBP_MODES[value][0]} is not supported by this pbpctrl version")
    stop_flatpak_budslink()
    run_text(["pbpctrl", "-d", address, "set", "anc", target])
    actual = run_text(["pbpctrl", "-d", address, "get", "anc"]).lower()
    if actual != target:
        raise RuntimeError(f"Pixel Buds remained in {actual} mode")
    return {"ok": True, "confirmed": True, "path": path, "value": value}


def set_mode(path: str, value_text: str) -> dict[str, Any]:
    value = int(value_text)
    if PIXEL_PATH.fullmatch(path):
        return set_pbp_mode(path, value)
    if not DEVICE_PATH.fullmatch(path):
        raise ValueError("Invalid BudsLink device path")
    if value not in range(1, 5):
        raise ValueError("Invalid noise-control mode")
    start_and_hold()
    busctl("call", SERVICE, path, DEVICE_IFACE, "UiAction", "si", "toggle1State", str(value))
    return {"ok": True, "confirmed": False, "path": path, "value": value}


def release() -> dict[str, Any]:
    if budslink_has_owner():
        call("ReleaseService", "s", CLIENT_ID)
    return {"ok": True}


def main() -> int:
    try:
        command = sys.argv[1] if len(sys.argv) > 1 else "status"
        if command == "status" and len(sys.argv) == 2:
            result = read_status()
        elif command == "mode" and len(sys.argv) == 4:
            result = set_mode(sys.argv[2], sys.argv[3])
        elif command == "release" and len(sys.argv) == 2:
            result = release()
        else:
            raise ValueError("Usage: budsctl.py status|mode DEVICE VALUE|release")
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
        return 0
    except FileNotFoundError as error:
        print(json.dumps({"ok": False, "available": False, "error": f"{error.filename} is not installed"}))
    except subprocess.TimeoutExpired:
        print(json.dumps({"ok": False, "available": False, "error": "The headset backend did not respond"}))
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "The headset backend failed").strip().splitlines()[-1]
        print(json.dumps({"ok": False, "available": False, "error": detail}))
    except (RuntimeError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "available": True, "error": str(error)}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())