#!/usr/bin/env bash
#
# Akkustand des USB-Headsets -- ueber headsetcontrol (liest die Logitech-
# HID++-Antwort, keine Netzwerkverbindung noetig).
#
# Ausgegeben wird immer JSON: {"ok":false} wenn kein Geraet erkannt wird
# (aus, Dongle nicht da, oder ein Modell ohne CAP_BATTERY_STATUS) -- die
# Leiste blendet die Zelle dann aus, statt mit "—" herumzustehen.
set -uo pipefail

fail() {
	printf '{"ok":false}\n'
	exit 0
}

command -v headsetcontrol >/dev/null 2>&1 || fail
command -v python3 >/dev/null 2>&1 || fail

raw="$(headsetcontrol -o json 2>/dev/null)" || fail
[ -n "$raw" ] || fail

NB_RAW="$raw" python3 - <<'PY'
import json
import os

try:
    data = json.loads(os.environ["NB_RAW"])
    dev = next(
        (d for d in data.get("devices") or [] if d.get("status") == "success" and "battery" in d),
        None,
    )
    if dev is None:
        raise ValueError

    bat = dev["battery"]
    status = bat.get("status", "")
    level = bat.get("level", -1)
    if status not in ("BATTERY_AVAILABLE", "BATTERY_CHARGING") or level < 0:
        raise ValueError

    print(json.dumps({
        "ok": True,
        "geraet": dev.get("product") or dev.get("device") or "Headset",
        "level": level,
        "laedt": status == "BATTERY_CHARGING",
    }, ensure_ascii=False))
except Exception:
    print(json.dumps({"ok": False}))
PY
