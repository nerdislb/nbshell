#!/usr/bin/env python3
"""Geraete in der Naehe finden und ihnen etwas schicken -- LocalSend-Protokoll.

Warum selbst gebaut und nicht die App gestartet: LocalSend ist ein
Flutter-Programm mit eigenem Fenster. Wer nur eine Datei ans Telefon geben
will, startet dafuer keine zweite Oberflaeche. Omarchys `Nearby`-Plugin loest
das mit einem vorkompilierten Rust-Helfer; hier reicht python3, das ohnehin
Pflicht ist (`plugins.sh`, `themes.sh`, `speedtest.sh` brauchen es alle).

Vom Protokoll (v2) wird der Teil umgesetzt, den man wirklich braucht:

    discover   Multicast-Ankuendigung schicken, Antworten einsammeln
    register   ein bekanntes Geraet direkt fragen (ohne Multicast)
    send       Dateien uebertragen
    text       Text als Datei uebertragen
    me         die eigene Kennung

EMPFANGEN kann das hier NICHT. Dafuer braeuchte es einen dauerhaft laufenden
HTTPS-Server mit eigenem Zertifikat, eine Zustimmungsabfrage und einen offenen
Port in der Firewall -- das ist ein eigenes Stueck Arbeit und gehoert nicht in
ein Skript, das sonst nur auf Zuruf laeuft. Zum Empfangen bleibt die App.

Alle Gegenstellen sprechen HTTPS mit selbstsigniertem Zertifikat; geprueft wird
es deshalb nicht. Das ist kein Versehen: im LocalSend-Protokoll ist der
Fingerabdruck die Kennung, nicht eine Zertifikatskette. Wer im selben WLAN
mitlesen will, muesste sich als Geraet ausgeben -- weshalb man nur an Geraete
schickt, die man in der Liste wiedererkennt.
"""

import json
import os
import socket
import ssl
import struct
import sys
import time
import urllib.error
import urllib.request
import uuid

GRUPPE = "224.0.0.167"
PORT = 53317
VERSION = "2.0"

STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "nbshell",
)

# Selbstsignierte Zertifikate sind hier der Normalfall, siehe Kopf.
KONTEXT = ssl.create_default_context()
KONTEXT.check_hostname = False
KONTEXT.verify_mode = ssl.CERT_NONE


def eigene_kennung():
    """Alias und Fingerabdruck -- beide bleiben, einmal vergeben.

    Der Fingerabdruck ist im Protokoll die Identitaet: wechselt er, ist man
    fuer die Gegenstelle ein neues, unbekanntes Geraet und muss erneut
    bestaetigt werden. Deshalb liegt er auf der Platte und wird nicht bei
    jedem Aufruf gewuerfelt.
    """
    pfad = os.path.join(STATE, "nearby.json")
    try:
        with open(pfad) as f:
            d = json.load(f)
        if d.get("fingerprint"):
            return d
    except Exception:
        pass

    d = {
        "alias": os.environ.get("NBSHELL_NEARBY_ALIAS") or socket.gethostname(),
        "fingerprint": uuid.uuid4().hex.upper(),
    }
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(pfad, "w") as f:
            json.dump(d, f)
    except Exception:
        pass
    return d


def eigene_info(announce=False):
    ich = eigene_kennung()
    return {
        "alias": ich["alias"],
        "version": VERSION,
        "deviceModel": "nbshell",
        "deviceType": "desktop",
        "fingerprint": ich["fingerprint"],
        "port": PORT,
        # Wir nehmen nichts entgegen -- siehe Kopf. `download: false` sagt der
        # Gegenstelle ausserdem, dass sie bei uns nichts abholen kann.
        "protocol": "http",
        "download": False,
        "announce": announce,
    }


def cmd_me():
    print(json.dumps(eigene_info(), ensure_ascii=False))


def cmd_discover(sekunden=3.0):
    """Einmal rufen, dann zuhoeren.

    Passives Lauschen allein genuegt nicht: LocalSend kuendigt sich vor allem
    beim Start an und danach selten. Wer nur wartet, sieht ein Geraet, das seit
    zehn Minuten offen ist, nie. Die Ankuendigung mit `announce: true` ist die
    Aufforderung zu antworten -- darauf melden sich alle sofort.
    """
    ich = eigene_info(announce=True)

    horcher = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    horcher.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        # Ohne das bekommt nur EIN Prozess die Pakete -- und wenn die
        # LocalSend-App nebenher laeuft, ist sie das.
        horcher.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    try:
        horcher.bind(("", PORT))
    except OSError as e:
        print(json.dumps({"ok": False, "grund": f"Port {PORT} belegt: {e}"}))
        return
    horcher.setsockopt(
        socket.IPPROTO_IP,
        socket.IP_ADD_MEMBERSHIP,
        struct.pack("4sl", socket.inet_aton(GRUPPE), socket.INADDR_ANY),
    )
    horcher.settimeout(0.5)

    rufer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rufer.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    try:
        rufer.sendto(json.dumps(ich).encode(), (GRUPPE, PORT))
    except OSError as e:
        print(json.dumps({"ok": False, "grund": f"Ankuendigung ging nicht raus: {e}"}))
        return

    gefunden = {}
    ende = time.time() + sekunden
    while time.time() < ende:
        try:
            daten, absender = horcher.recvfrom(8192)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            d = json.loads(daten)
        except Exception:
            continue
        fp = d.get("fingerprint")
        if not fp or fp == ich["fingerprint"]:
            continue
        gefunden[fp] = {
            "alias": d.get("alias") or absender[0],
            "model": d.get("deviceModel") or "",
            "type": d.get("deviceType") or "",
            "ip": absender[0],
            "port": d.get("port") or PORT,
            "protocol": d.get("protocol") or "https",
            "fingerprint": fp,
            "download": bool(d.get("download")),
        }

    print(json.dumps({"ok": True, "devices": list(gefunden.values())}, ensure_ascii=False))


def _url(geraet, pfad):
    schema = "https" if (geraet.get("protocol") or "https") == "https" else "http"
    return f"{schema}://{geraet['ip']}:{geraet['port']}/api/localsend/v2/{pfad}"


def _post(url, daten, roh=False, timeout=30):
    koerper = daten if roh else json.dumps(daten).encode()
    kopf = {"Content-Type": "application/octet-stream" if roh else "application/json"}
    req = urllib.request.Request(url, data=koerper, headers=kopf)
    with urllib.request.urlopen(req, timeout=timeout, context=KONTEXT) as r:
        return r.status, r.read()


def cmd_register(ip, port=PORT, protocol="https"):
    """Ein bekanntes Geraet direkt fragen -- ohne Multicast.

    Nuetzlich, wenn der Router Multicast schluckt (manche Gast-WLANs tun das)
    oder die Gegenstelle in einem anderen Segment steht.
    """
    geraet = {"ip": ip, "port": int(port), "protocol": protocol}
    try:
        _, antwort = _post(_url(geraet, "register"), eigene_info(), timeout=5)
        d = json.loads(antwort)
    except Exception as e:
        print(json.dumps({"ok": False, "grund": f"{type(e).__name__}: {e}"}))
        return
    print(json.dumps({
        "ok": True,
        "devices": [{
            "alias": d.get("alias") or ip,
            "model": d.get("deviceModel") or "",
            "type": d.get("deviceType") or "",
            "ip": ip,
            "port": int(port),
            "protocol": protocol,
            "fingerprint": d.get("fingerprint") or "",
            "download": bool(d.get("download")),
        }],
    }, ensure_ascii=False))


def _senden(geraet, dateien):
    """prepare-upload, dann je Datei ein upload.

    Die Gegenstelle fragt ihren Benutzer waehrend `prepare-upload`, ob sie das
    annehmen will -- der Aufruf haengt also so lange, wie drueben jemand
    ueberlegt. Deshalb steht dort eine grosszuegige Frist; ein Abbruch nach
    fuenf Sekunden waere ein Nein, das niemand gesagt hat.
    """
    beschreibung = {}
    for i, pfad in enumerate(dateien):
        beschreibung[str(i)] = {
            "id": str(i),
            "fileName": os.path.basename(pfad),
            "size": os.path.getsize(pfad),
            "fileType": "text/plain" if pfad.endswith(".txt") else "application/octet-stream",
        }

    status, antwort = _post(
        _url(geraet, "prepare-upload"),
        {"info": eigene_info(), "files": beschreibung},
        timeout=180,
    )
    # 204 heisst: angenommen, aber nichts zu holen. Kommt vor, wenn die
    # Gegenstelle die Dateien schon hat.
    if status == 204 or not antwort:
        return {"ok": True, "hinweis": "nichts zu uebertragen"}

    sitzung = json.loads(antwort)
    sid = sitzung.get("sessionId")
    tokens = sitzung.get("files") or {}
    if not sid or not tokens:
        return {"ok": False, "grund": "Gegenstelle hat keine Sitzung eroeffnet"}

    fertig = []
    for fid, token in tokens.items():
        pfad = dateien[int(fid)]
        with open(pfad, "rb") as f:
            inhalt = f.read()
        url = _url(geraet, f"upload?sessionId={sid}&fileId={fid}&token={token}")
        _post(url, inhalt, roh=True, timeout=600)
        fertig.append(os.path.basename(pfad))
    return {"ok": True, "gesendet": fertig}


def cmd_send(ip, port, protocol, dateien):
    geraet = {"ip": ip, "port": int(port), "protocol": protocol}
    fehlend = [p for p in dateien if not os.path.isfile(p)]
    if fehlend:
        print(json.dumps({"ok": False, "grund": "nicht gefunden: " + ", ".join(fehlend)}))
        return
    try:
        print(json.dumps(_senden(geraet, dateien), ensure_ascii=False))
    except urllib.error.HTTPError as e:
        # 403 heisst hier fast immer: drueben wurde abgelehnt.
        grund = "abgelehnt" if e.code == 403 else f"HTTP {e.code}"
        print(json.dumps({"ok": False, "grund": grund}))
    except Exception as e:
        print(json.dumps({"ok": False, "grund": f"{type(e).__name__}: {e}"}))


def cmd_text(ip, port, protocol, text):
    """Text als Datei -- so sieht es das Protokoll vor.

    Ein eigener Texttyp existiert zwar, wird aber nicht von jeder Gegenstelle
    unterstuetzt; eine .txt versteht jede.
    """
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        pfad = os.path.join(tmp, time.strftime("nbshell-%Y%m%d-%H%M%S.txt"))
        with open(pfad, "w") as f:
            f.write(text)
        cmd_send(ip, port, protocol, [pfad])


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2
    befehl = sys.argv[1]
    rest = sys.argv[2:]
    if befehl == "me":
        cmd_me()
    elif befehl == "discover":
        cmd_discover(float(rest[0]) if rest else 3.0)
    elif befehl == "register":
        cmd_register(rest[0], rest[1] if len(rest) > 1 else PORT,
                     rest[2] if len(rest) > 2 else "https")
    elif befehl == "send":
        cmd_send(rest[0], rest[1], rest[2], rest[3:])
    elif befehl == "text":
        cmd_text(rest[0], rest[1], rest[2], rest[3])
    else:
        print(json.dumps({"ok": False, "grund": f"unbekannt: {befehl}"}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
