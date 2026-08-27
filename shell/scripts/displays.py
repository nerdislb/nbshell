#!/usr/bin/env python3
"""Read, apply, and persist output settings owned by nbshell."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path


CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
STATE_FILE = CONFIG_HOME / "nbshell" / "displays.json"
NIRI_FILE = CONFIG_HOME / "niri" / "nbshell-outputs.kdl"
UMBRIEL_FILE = CONFIG_HOME / "umbriel" / "nbshell-outputs.toml"
OUTPUT_RE = re.compile(r"^[A-Za-z0-9_.:-]+$")
MODE_RE = re.compile(r"^(auto|\d+x\d+@\d+(?:\.\d+)?)$")
TRANSFORMS = {"normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"}


def niri_json(command: str) -> dict:
    result = subprocess.run(["niri", "msg", "--json", command], text=True, capture_output=True, check=True)
    value = json.loads(result.stdout)
    return value if isinstance(value, dict) else {}


def outputs() -> dict:
    return niri_json("outputs")


def backend() -> str:
    forced = os.environ.get("NBSHELL_COMPOSITOR", "").lower()
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    return "umbriel" if forced == "umbriel" or os.environ.get("UMBRIEL_SOCKET") or "umbriel" in desktop else "niri"


def load_state() -> dict:
    try:
        value = json.loads(STATE_FILE.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def mode_label(mode: dict) -> str:
    refresh = int(mode.get("refresh_rate", 0)) / 1000
    return f"{int(mode.get('width', 0))}x{int(mode.get('height', 0))}@{refresh:.3f}"


def status() -> dict:
    if backend() == "umbriel":
        result = subprocess.run(["wlr-randr", "--json"], text=True, capture_output=True, check=True)
        rows = []
        for row in json.loads(result.stdout):
            position = row.get("position") or {}
            modes = [{
                "label": f'{int(mode.get("width", 0))}x{int(mode.get("height", 0))}@{float(mode.get("refresh", 0)):.3f}',
                "width": int(mode.get("width", 0)), "height": int(mode.get("height", 0)),
                "refresh": round(float(mode.get("refresh", 0)), 3),
                "preferred": bool(mode.get("preferred")), "current": bool(mode.get("current")),
            } for mode in row.get("modes") or []]
            rows.append({
                "name": str(row.get("name") or ""), "make": str(row.get("make") or ""),
                "model": str(row.get("model") or ""), "enabled": bool(row.get("enabled")),
                "focused": False, "x": int(position.get("x", 0)), "y": int(position.get("y", 0)),
                "width": next((m["width"] for m in modes if m["current"]), 0),
                "height": next((m["height"] for m in modes if m["current"]), 0),
                "scale": float(row.get("scale", 1)), "transform": str(row.get("transform") or "normal"),
                "vrrSupported": True, "vrrEnabled": bool(row.get("adaptive_sync")), "modes": modes,
                "currentMode": next((m["label"] for m in modes if m["current"]), ""),
            })
        rows.sort(key=lambda item: (item["x"], item["y"], item["name"]))
        return {"outputs": rows, "saved": load_state(), "backend": "umbriel"}
    raw = outputs()
    focused = ""
    try:
        focused = str(niri_json("focused-output").get("name") or "")
    except (subprocess.SubprocessError, ValueError):
        pass
    rows = []
    for name, row in raw.items():
        logical = row.get("logical") or {}
        current_index = row.get("current_mode")
        modes = []
        for index, mode in enumerate(row.get("modes") or []):
            modes.append({
                "label": mode_label(mode),
                "width": int(mode.get("width", 0)),
                "height": int(mode.get("height", 0)),
                "refresh": round(int(mode.get("refresh_rate", 0)) / 1000, 3),
                "preferred": bool(mode.get("is_preferred", False)),
                "current": current_index == index,
            })
        rows.append({
            "name": str(name),
            "make": str(row.get("make") or ""),
            "model": str(row.get("model") or ""),
            "enabled": bool(logical),
            "focused": name == focused,
            "x": int(logical.get("x", 0)),
            "y": int(logical.get("y", 0)),
            "width": int(logical.get("width", 0)),
            "height": int(logical.get("height", 0)),
            "scale": float(logical.get("scale", 1)),
            "transform": str(logical.get("transform") or "Normal").lower(),
            "vrrSupported": bool(row.get("vrr_supported", False)),
            "vrrEnabled": bool(row.get("vrr_enabled", False)),
            "modes": modes,
            "currentMode": next((mode["label"] for mode in modes if mode["current"]), ""),
        })
    rows.sort(key=lambda row: (row["x"], row["y"], row["name"]))
    return {"outputs": rows, "saved": load_state(), "backend": "niri"}


def validate_name(name: str) -> None:
    if not OUTPUT_RE.fullmatch(name):
        raise SystemExit(f"Invalid output name: {name}")


def run_output(name: str, *args: str) -> None:
    validate_name(name)
    if backend() == "niri":
        subprocess.run(["niri", "msg", "output", name, *args], check=True)
        return
    mapping = {
        "mode": ["--mode"], "scale": ["--scale"], "transform": ["--transform"],
        "on": ["--on"], "off": ["--off"],
    }
    if args[:2] == ("position", "set"):
        options = ["--pos", f"{args[2]},{args[3]}"]
    elif args[:2] == ("position", "auto"):
        raise SystemExit("Automatic placement is not supported by wlr-randr; choose a relative position")
    else:
        options = mapping.get(args[0], []) + list(args[1:])
    if not options: raise SystemExit("Unsupported Umbriel output operation")
    subprocess.run(["wlr-randr", "--output", name, *options], check=True)


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    tmp.replace(STATE_FILE)
    render_kdl(state)
    render_toml(state)


def render_toml(state: dict) -> None:
    lines = ["# Generated by nbshell display. Include from config.toml."]
    for name in sorted(state):
        validate_name(name); row = state[name]
        lines.append(f'\n[output."{name}"]')
        if row.get("enabled") is not None: lines.append(f'enabled = {str(bool(row["enabled"])).lower()}')
        if row.get("mode"): lines.append(f'mode = "{row["mode"]}"')
        if row.get("scale") is not None: lines.append(f'scale = {float(row["scale"]):g}')
        if row.get("transform"): lines.append(f'transform = "{row["transform"]}"')
        if row.get("x") is not None and row.get("y") is not None:
            lines.append(f'position = [{int(row["x"])}, {int(row["y"])}]')
    UMBRIEL_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = UMBRIEL_FILE.with_suffix(".tmp"); tmp.write_text("\n".join(lines) + "\n"); tmp.replace(UMBRIEL_FILE)


def render_kdl(state: dict) -> None:
    lines = ["// Generated by nbshell display. Edit through the display panel or CLI."]
    for name in sorted(state):
        validate_name(name)
        row = state[name]
        lines.append(f'output "{name}" {{')
        if row.get("enabled") is False:
            lines.append("    off")
        else:
            if row.get("mode"): lines.append(f'    mode "{row["mode"]}"')
            if row.get("scale") is not None: lines.append(f'    scale {float(row["scale"]):g}')
            if row.get("transform"): lines.append(f'    transform "{row["transform"]}"')
            if row.get("x") is not None and row.get("y") is not None:
                lines.append(f'    position x={int(row["x"])} y={int(row["y"])}')
        lines.append("}")
    NIRI_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = NIRI_FILE.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(NIRI_FILE)


def update(name: str, key: str, value) -> None:
    state = load_state()
    row = dict(state.get(name) or {})
    row[key] = value
    if key != "enabled": row["enabled"] = True
    state[name] = row
    save_state(state)


def set_value(name: str, key: str, value: str) -> None:
    validate_name(name)
    if key == "mode":
        if not MODE_RE.fullmatch(value): raise SystemExit("Mode must be auto or WIDTHxHEIGHT@HZ")
        if backend() == "umbriel" and value == "auto":
            subprocess.run(["wlr-randr", "--output", name, "--preferred"], check=True)
        else:
            run_output(name, "mode", value)
        update(name, "mode", value)
    elif key == "scale":
        scale = float(value)
        if not 0.5 <= scale <= 4: raise SystemExit("Scale must be between 0.5 and 4")
        run_output(name, "scale", f"{scale:g}")
        update(name, "scale", scale)
    elif key == "transform":
        transform = value.lower().replace("normal", "normal")
        if transform not in TRANSFORMS: raise SystemExit("Unsupported transform")
        run_output(name, "transform", transform)
        update(name, "transform", transform)
    elif key == "enabled":
        enabled = value.lower() in {"1", "true", "yes", "on"}
        if not enabled:
            active = [row for row in status()["outputs"] if row["enabled"]]
            if len(active) <= 1: raise SystemExit("Refusing to turn off the only enabled output")
        update(name, "enabled", enabled)
        if backend() == "umbriel":
            subprocess.run(["umbriel", "msg", "config-reload"], check=True)
        else:
            run_output(name, "on" if enabled else "off")
    else:
        raise SystemExit(f"Unknown property: {key}")


def place(name: str, relation: str, reference: str) -> None:
    if relation == "auto":
        state = load_state(); row = dict(state.get(name) or {}); row.pop("x", None); row.pop("y", None); state[name] = row; save_state(state)
        if backend() == "umbriel":
            subprocess.run(["umbriel", "msg", "config-reload"], check=True)
        else:
            run_output(name, "position", "auto")
        return
    validate_name(reference)
    rows = {row["name"]: row for row in status()["outputs"]}
    target, anchor = rows.get(name), rows.get(reference)
    if not target or not anchor or not target["enabled"] or not anchor["enabled"]:
        raise SystemExit("Both outputs must be enabled")
    if relation == "left": x, y = anchor["x"] - target["width"], anchor["y"]
    elif relation == "right": x, y = anchor["x"] + anchor["width"], anchor["y"]
    elif relation == "above": x, y = anchor["x"], anchor["y"] - target["height"]
    elif relation == "below": x, y = anchor["x"], anchor["y"] + anchor["height"]
    elif relation == "same": x, y = anchor["x"], anchor["y"]
    else: raise SystemExit("Position must be left, right, above, below, same, or auto")
    if backend() == "umbriel" and relation != "same":
        # Umbriel normalizes the global output coordinate space. Supplying a
        # calculated absolute --pos can therefore be moved beside the anchor
        # even though the requested topology was above/below it. Let the
        # output-management protocol express the relationship directly.
        relative_flag = {
            "left": "--left-of", "right": "--right-of",
            "above": "--above", "below": "--below",
        }[relation]
        subprocess.run(["wlr-randr", "--output", name, relative_flag, reference], check=True)
    else:
        run_output(name, "position", "set", str(x), str(y))

    # Umbriel may translate every output after a relative move. Persist its
    # authoritative coordinates for all connected outputs, not only the one
    # that was moved, so config reloads reproduce the live topology exactly.
    live_rows = status()["outputs"]
    state = load_state()
    for live in live_rows:
        if not live["enabled"]:
            continue
        row = dict(state.get(live["name"]) or {})
        row.update({"x": live["x"], "y": live["y"], "enabled": True})
        state[live["name"]] = row
    save_state(state)


def main() -> int:
    parser = argparse.ArgumentParser(description="nbshell display control")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    set_p = sub.add_parser("set"); set_p.add_argument("output"); set_p.add_argument("property", choices=["mode", "scale", "transform", "enabled"]); set_p.add_argument("value")
    place_p = sub.add_parser("place"); place_p.add_argument("output"); place_p.add_argument("relation", choices=["left", "right", "above", "below", "same", "auto"]); place_p.add_argument("reference", nargs="?", default="")
    args = parser.parse_args()
    if args.command == "status": print(json.dumps(status())); return 0
    if args.command == "set": set_value(args.output, args.property, args.value); return 0
    if args.command == "place": place(args.output, args.relation, args.reference); return 0
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, ValueError) as error:
        raise SystemExit(str(error))
