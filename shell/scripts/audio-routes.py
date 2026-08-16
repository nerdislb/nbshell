#!/usr/bin/env python3
"""Structured Pulse/PipeWire application routes for Audio.qml."""

import json
import subprocess
import sys


def pactl(*args):
    return subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=5)


def listing():
    sinks_result = pactl("-f", "json", "list", "sinks")
    inputs_result = pactl("-f", "json", "list", "sink-inputs")
    if sinks_result.returncode or inputs_result.returncode:
        raise SystemExit((sinks_result.stderr or inputs_result.stderr).strip())
    sinks_raw = json.loads(sinks_result.stdout or "[]")
    inputs_raw = json.loads(inputs_result.stdout or "[]")
    sinks = [{"index": int(s.get("index", -1)), "name": str(s.get("name", "")),
              "label": str(s.get("description") or s.get("name", ""))}
             for s in sinks_raw if s.get("name")]
    by_index = {s["index"]: s for s in sinks}
    streams = []
    for stream in inputs_raw:
        props = stream.get("properties") or {}
        sink_index = int(stream.get("sink", -1))
        streams.append({
            "index": int(stream.get("index", -1)),
            "name": str(props.get("application.name") or props.get("media.name") or "Anwendung"),
            "binary": str(props.get("application.process.binary") or ""),
            "sinkIndex": sink_index,
            "sink": by_index.get(sink_index, {}).get("name", ""),
            "sinkLabel": by_index.get(sink_index, {}).get("label", "unbekannte Ausgabe")
        })
    print(json.dumps({"sinks": sinks, "streams": streams}, ensure_ascii=False))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "list"
    if command == "list":
        listing()
    elif command == "set" and len(sys.argv) == 4:
        stream = int(sys.argv[2]); sink = sys.argv[3]
        result = pactl("move-sink-input", str(stream), sink)
        if result.returncode:
            raise SystemExit(result.stderr.strip())
    else:
        raise SystemExit("Aufruf: audio-routes.py list|set STREAM SINK")


if __name__ == "__main__": main()
