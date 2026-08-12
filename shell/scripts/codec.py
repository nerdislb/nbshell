#!/usr/bin/env python3
"""Welcher Bluetooth-Codec gerade laeuft -- und welche es noch gaebe.

Der Gedanke stammt von bt.codecs (nightdevil00): am Bluetooth-Hoerer
entscheidet der Codec ueber die Klangqualitaet, und man sieht ihm nirgends an,
welcher gerade ausgehandelt wurde. Unter PipeWire ist die Antwort ein
Kartenprofil -- jeder Codec ist eines, und Umschalten heisst Profil wechseln.

Zwei Dinge, die man dabei wissen muss:

  * Das Profil `a2dp-sink` OHNE Anhaengsel ist nicht "irgendein A2DP", sondern
    ein Codec wie jeder andere -- hier AAC. Wer nach dem Namen sortiert, haelt
    es fuer den Standard und faellt darauf herein (scripts/ton.sh tat das und
    holte damit jedesmal SBC zurueck, den schlechtesten der vier).
  * Die Prioritaet in der Klammer ist PipeWires eigene Reihenfolge. Sie ist die
    ehrlichste Quelle dafuer, was "das Beste" ist -- besser als eine Liste von
    Codec-Namen, die hier gepflegt werden muesste.
"""

import json
import re
import subprocess
import sys

# "	a2dp-sink-sbc_xq: High Fidelity Playback (A2DP Sink, codec SBC-XQ)
#      (sinks: 1, sources: 0, priority: 132, available: yes)"
PROFIL = re.compile(
    r"^\s+([A-Za-z0-9_+-]+):\s+(.*?)\s+\(sinks:.*?priority:\s*(\d+),\s*available:\s*(\w+)\)"
)
CODEC = re.compile(r"codec\s+([A-Za-z0-9_.+-]+)")


def pactl(*args):
    try:
        return subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def karten():
    """Die Bluetooth-Karte samt ihrer Profile. Nur die erste -- mehr als einen
    Hoerer gleichzeitig gibt es in der Praxis nicht, und die Leiste haette
    ohnehin keinen Platz fuer zwei Reihen."""
    text = pactl("list", "cards")
    if not text:
        return None

    karte = None
    for zeile in text.splitlines():
        name = re.match(r"^\s+Name:\s+(bluez_card\.\S+)", zeile)
        if name:
            karte = {"karte": name.group(1), "geraet": "", "aktiv": "", "profile": []}
            continue
        if karte is None:
            continue
        # Eine zweite Karte beendet die erste.
        if re.match(r"^\s+Name:\s+(?!bluez_card)", zeile) and karte["profile"]:
            break

        beschreibung = re.match(r'^\s+device\.description = "(.*)"', zeile)
        if beschreibung:
            karte["geraet"] = beschreibung.group(1)
            continue

        aktiv = re.match(r"^\s+Active Profile:\s+(\S+)", zeile)
        if aktiv:
            karte["aktiv"] = aktiv.group(1)
            continue

        treffer = PROFIL.match(zeile)
        if treffer:
            profil, text_, prio, verfuegbar = treffer.groups()
            codec = CODEC.search(text_)
            karte["profile"].append({
                "profil": profil,
                # Ob ueberhaupt ein Codec drinsteht, entscheidet, ob es zur
                # Auswahl gehoert: `off` ist auch ein Profil, aber keine Wahl
                # zwischen Klangqualitaeten.
                "codec": codec.group(1) if codec else profil,
                "istCodec": codec is not None,
                "prio": int(prio),
                "da": verfuegbar == "yes",
                "telefonie": profil.startswith("headset"),
            })
    return karte


def main():
    karte = karten()
    if not karte:
        print(json.dumps({"ok": False, "grund": "kein Bluetooth-Tongeraet"}))
        return

    # Nur Wiedergabeprofile zur Auswahl: die Headset-Profile stellt das System
    # beim Telefonieren selbst ein, und wer sie von Hand waehlt, macht sich den
    # Klang kaputt, ohne dass jemand anruft.
    auswahl = sorted(
        (p for p in karte["profile"] if p["da"] and p["istCodec"] and not p["telefonie"]),
        key=lambda p: -p["prio"],
    )
    aktiv = next((p for p in karte["profile"] if p["profil"] == karte["aktiv"]), None)

    print(json.dumps({
        "ok": True,
        "karte": karte["karte"],
        "geraet": karte["geraet"],
        "aktiv": karte["aktiv"],
        "codec": aktiv["codec"] if aktiv else "",
        "telefonie": bool(aktiv and aktiv["telefonie"]),
        "beste": auswahl[0]["profil"] if auswahl else "",
        "codecs": auswahl,
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        print(json.dumps({"ok": False, "grund": str(e)}, ensure_ascii=False))
        sys.exit(1)
