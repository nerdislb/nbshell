#!/usr/bin/env python3
"""Turn Formula 1's live SignalR feed into a small atomic JSON snapshot."""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import threading
import time
import unicodedata
from pathlib import Path
from typing import Any

import requests
from signalrcore.hub_connection_builder import HubConnectionBuilder
from signalrcore.messages.completion_message import CompletionMessage


CONNECTION_URL = "wss://livetiming.formula1.com/signalrcore"
NEGOTIATE_URL = "https://livetiming.formula1.com/signalrcore/negotiate"
TOPICS = [
    "Heartbeat",
    "DriverList",
    "ExtrapolatedClock",
    "RaceControlMessages",
    "SessionInfo",
    "SessionStatus",
    "TimingAppData",
    "TimingStats",
    "TimingData",
    "TrackStatus",
    "WeatherData",
    "SessionData",
    "TopThree",
    "LapCount",
]


def deep_merge(current: Any, update: Any) -> Any:
    if isinstance(current, list) and isinstance(update, dict):
        merged_list = list(current)
        for key, value in update.items():
            try:
                index = int(key)
            except (TypeError, ValueError):
                continue
            while len(merged_list) <= index:
                merged_list.append({})
            merged_list[index] = deep_merge(merged_list[index], value)
        return merged_list
    if not isinstance(current, dict) or not isinstance(update, dict):
        return update
    merged = dict(current)
    for key, value in update.items():
        merged[key] = deep_merge(merged.get(key), value)
    return merged


def clean_gap(value: Any) -> Any:
    if value in (None, ""):
        return ""
    if isinstance(value, str):
        return value.removeprefix("+")
    return value


def clean_text(value: Any, limit: int) -> str:
    text = "".join(
        character for character in str(value or "")
        if character not in "<>" and not unicodedata.category(character).startswith("C")
    )
    return text[:limit]


def track_status(value: Any) -> str:
    return {
        "1": "green",
        "2": "yellow",
        "4": "sc",
        "5": "red",
        "6": "vsc",
        "7": "vsc",
    }.get(str(value), "green")


def indexed_values(value: Any) -> list[Any]:
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return [item for _, item in sorted(
            value.items(), key=lambda pair: int(pair[0]) if str(pair[0]).isdigit() else 999
        )]
    return []


class LiveBridge:
    def __init__(self, output: Path) -> None:
        self.output = output
        self.state: dict[str, Any] = {}
        self.lock = threading.Lock()
        self.connection = None
        self.connected = False
        self.last_message = 0.0
        self.stopping = False

    def consume(self, message: Any) -> None:
        if isinstance(message, CompletionMessage):
            values = (message.result or {}).items()
        elif isinstance(message, list) and len(message) >= 2:
            values = [(message[0], message[1])]
        else:
            return

        with self.lock:
            for topic, payload in values:
                if isinstance(payload, str):
                    try:
                        payload = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                self.state[str(topic)] = deep_merge(self.state.get(str(topic)), payload)
            self.last_message = time.time()
            self.write_snapshot()

    def snapshot(self) -> dict[str, Any]:
        drivers_raw = self.state.get("DriverList") or {}
        timing = (self.state.get("TimingData") or {}).get("Lines") or {}
        timing_app = (self.state.get("TimingAppData") or {}).get("Lines") or {}
        session = self.state.get("SessionStatus") or {}
        track = self.state.get("TrackStatus") or {}
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        drivers = {}
        positions = {}
        gaps = {}
        details = {}
        for number, row in drivers_raw.items():
            if str(number).startswith("_") or not isinstance(row, dict):
                continue
            drivers[str(number)] = {
                "acronym": clean_text(row.get("Tla") or f"#{number}", 6),
                "team": clean_text(row.get("TeamName"), 32),
                "name": clean_text(row.get("FullName") or row.get("BroadcastName"), 64),
            }
        for number, row in timing.items():
            if str(number).startswith("_") or not isinstance(row, dict):
                continue
            position = row.get("Position") or row.get("Line")
            try:
                position = int(position)
            except (TypeError, ValueError):
                continue
            positions[str(number)] = {"position": position, "date": now}
            gaps[str(number)] = {
                "gap_to_leader": clean_gap(row.get("TimeDiffToFastest")),
                "interval": clean_gap(row.get("TimeDiffToPositionAhead")),
                "date": now,
            }
            app_row = timing_app.get(str(number)) or {}
            stints = indexed_values(app_row.get("Stints"))
            stint = stints[-1] if stints and isinstance(stints[-1], dict) else {}
            sectors = []
            for sector in indexed_values(row.get("Sectors"))[:3]:
                if not isinstance(sector, dict):
                    sector = {}
                value = clean_text(sector.get("Value"), 12)
                state = ""
                if sector.get("OverallFastest"):
                    state = "overall"
                elif sector.get("PersonalFastest"):
                    state = "personal"
                elif value:
                    state = "complete"
                sectors.append({"value": value, "state": state})
            while len(sectors) < 3:
                sectors.append({"value": "", "state": ""})
            best_lap = row.get("BestLapTime") or {}
            last_lap = row.get("LastLapTime") or {}
            try:
                tyre_laps = int(stint.get("TotalLaps") or 0)
            except (TypeError, ValueError):
                tyre_laps = 0
            details[str(number)] = {
                "compound": clean_text(stint.get("Compound"), 16),
                "tyreLaps": tyre_laps,
                "sectors": sectors,
                "bestLap": clean_text(best_lap.get("Value"), 16),
                "lastLap": clean_text(last_lap.get("Value"), 16),
                "inPit": bool(row.get("InPit")),
                "pitOut": bool(row.get("PitOut")),
            }

        status = str(session.get("Status") or session.get("Started") or "").lower()
        return {
            "ok": bool(drivers and positions),
            "connected": self.connected,
            "sessionLive": status in {"started", "active"},
            "trackStatus": track_status(track.get("Status")),
            "drivers": drivers,
            "positions": positions,
            "gaps": gaps,
            "details": details,
            "updatedAt": now,
        }

    def write_snapshot(self) -> None:
        self.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = self.output.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.snapshot(), separators=(",", ":")), encoding="utf-8")
        os.replace(temporary, self.output)

    def stop(self, *_args: Any) -> None:
        self.stopping = True
        if self.connection is not None:
            self.connection.stop()

    def run(self) -> int:
        headers: dict[str, str] = {}
        response = requests.options(NEGOTIATE_URL, timeout=15)
        # The endpoint currently answers OPTIONS with 405 while still setting
        # the AWS affinity cookie. signalrcore performs the real POST
        # negotiation afterwards, so only the cookie from this preflight is
        # relevant here.
        cookie = response.cookies.get("AWSALBCORS")
        if cookie:
            headers["Cookie"] = f"AWSALBCORS={cookie}"

        options = {
            "verify_ssl": True,
            # signalrcore requires a callable even for anonymous access.
            "access_token_factory": lambda: "",
            "headers": headers,
        }
        self.connection = (
            HubConnectionBuilder()
            .with_url(CONNECTION_URL, options=options)
            .build()
        )
        self.connection.on_open(self._opened)
        self.connection.on_close(self._closed)
        self.connection.on("feed", self.consume)
        self.connection.start()

        deadline = time.monotonic() + 15
        while not self.connected and time.monotonic() < deadline and not self.stopping:
            time.sleep(0.1)
        if not self.connected:
            raise RuntimeError("F1 live timing connection timed out")

        self.connection.send("Subscribe", [TOPICS], on_invocation=self.consume)
        while not self.stopping:
            if self.last_message and time.time() - self.last_message > 75:
                raise RuntimeError("F1 live timing stopped sending data")
            time.sleep(1)
        return 0

    def _opened(self) -> None:
        self.connected = True

    def _closed(self) -> None:
        self.connected = False


def self_test() -> int:
    merged = deep_merge({"Lines": {"1": {"Position": "2", "Gap": "x"}}},
                        {"Lines": {"1": {"Position": "1"}}})
    assert merged["Lines"]["1"] == {"Position": "1", "Gap": "x"}
    assert deep_merge([{"Value": "1"}], {"0": {"Status": 1}}) == [
        {"Value": "1", "Status": 1}
    ]
    assert track_status("6") == "vsc"
    assert clean_gap("+1.234") == "1.234"
    assert clean_text("<b>Driver</b>\n", 8) == "bDriver/"
    print("pit-wall live bridge self-test passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.output is None:
        parser.error("--output is required")

    bridge = LiveBridge(args.output)
    signal.signal(signal.SIGTERM, bridge.stop)
    signal.signal(signal.SIGINT, bridge.stop)
    try:
        return bridge.run()
    except Exception as error:
        print(f"pit-wall live bridge: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
