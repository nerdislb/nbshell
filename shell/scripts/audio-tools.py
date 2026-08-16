#!/usr/bin/env python3
"""Lokale Fokusgeraeusche und eine kleine EasyEffects-Steuerung."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

STATE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "nbshell-ambience.json"
COLORS = {"white": "white", "pink": "pink", "brown": "brown", "rain": "brown"}

def read_state():
    try: return json.loads(STATE.read_text())
    except Exception: return {}

def alive(state):
    pid = int(state.get("pid", 0))
    if pid <= 0: return False
    try:
        cmd = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ")
        os.kill(pid, 0)
        return b"anoisesrc" in cmd and b"nbshell-ambience" in cmd
    except Exception: return False

def stop():
    state = read_state()
    if alive(state):
        os.kill(int(state["pid"]), signal.SIGTERM)
    STATE.unlink(missing_ok=True)

def start(kind):
    if kind not in COLORS: raise SystemExit("unbekanntes Geraeusch")
    stop()
    amplitude = "0.035" if kind == "white" else "0.065"
    source = f"anoisesrc=color={COLORS[kind]}:amplitude={amplitude}:sample_rate=48000"
    if kind == "rain": source += ",highpass=f=180,lowpass=f=6500"
    proc = subprocess.Popen(["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", source,
                             "-f", "pulse", "-metadata", "title=nbshell-ambience", "nbshell Ambience"],
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    STATE.write_text(json.dumps({"pid": proc.pid, "kind": kind}))

def ee(*args, timeout=4):
    return subprocess.run(["easyeffects", *args], text=True, capture_output=True, timeout=timeout)

def ensure_ee():
    if subprocess.run(["pgrep", "-x", "easyeffects"], stdout=subprocess.DEVNULL).returncode != 0:
        subprocess.Popen(["easyeffects", "--service-mode"], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(30):
            time.sleep(.1)
            if subprocess.run(["pgrep", "-x", "easyeffects"], stdout=subprocess.DEVNULL).returncode == 0:
                break

def status():
    state = read_state()
    ambience = state.get("kind", "") if alive(state) else ""
    bypass = "unbekannt"
    presets = []
    try:
        ensure_ee()
        result = ee("--bypass", "3")
        value = (result.stdout + result.stderr).strip().lower()
        bypass = "an" if "1" in value or "true" in value else "aus"
        result = ee("--presets")
        presets = [line.strip() for line in result.stdout.splitlines()
                   if line.strip() and not line.startswith("Available") and not line.startswith("No ")]
    except Exception: pass
    print(json.dumps({"ambience": ambience, "bypass": bypass, "presets": presets}, ensure_ascii=False))

cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
if cmd == "status": status()
elif cmd == "start": start(sys.argv[2]); status()
elif cmd == "stop": stop(); status()
elif cmd == "bypass":
    ensure_ee()
    try: ee("--bypass-toggle")
    except subprocess.TimeoutExpired: pass
    time.sleep(.3); status()
elif cmd == "preset":
    ensure_ee()
    try: ee("--load-preset", sys.argv[2])
    except subprocess.TimeoutExpired: pass
    time.sleep(.5); status()
else: raise SystemExit("status|start <art>|stop|bypass|preset <name>")
