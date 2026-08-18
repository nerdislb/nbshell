#!/usr/bin/env bash
#
# Durchsatz messen -- Ping, Herunterladen, Hochladen.
#
# Ausgegeben wird JSON, damit das Popout nichts zerlegen muss:
#
#   {"ok":true,"ping":12.4,"down":94.2,"up":38.1,"server":"Wien, A1"}
#   {"ok":false,"grund":"speedtest-cli fehlt — sudo pacman -S speedtest-cli"}
#
# Zwei Programme kommen in Frage. Ooklas eigenes `speedtest` misst genauer und
# kennt mehr Gegenstellen, ist aber im AUR und will beim ersten Start eine
# Lizenz bestaetigt haben -- deshalb ist `speedtest-cli` (extra, Python) die
# erste Wahl, wenn beide da sind: es laeuft ohne Rueckfrage.
#
# Die Messung dauert. Wer sie startet, weiss das; das Popout zeigt so lange
# "misst …". Eine Zeitgrenze steht trotzdem drum -- eine Gegenstelle, die nicht
# antwortet, darf den Prozess nicht bis zum Abmelden offen lassen.
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

fail() {
	printf '{"ok":false,"grund":"%s"}\n' "$1"
	exit 0
}

if have speedtest-cli; then
	roh="$(timeout 120 speedtest-cli --json 2>/dev/null)" || fail "Test failed"
	[ -n "$roh" ] || fail "Test failed"
	SPEED_JSON="$roh" python3 - <<'PY'
import json, os

d = json.loads(os.environ["SPEED_JSON"])
srv = d.get("server", {}) or {}
name = ", ".join(x for x in [srv.get("name"), srv.get("sponsor")] if x)
print(json.dumps({
    "ok": True,
    # speedtest-cli rechnet in Bit je Sekunde, angezeigt wird Megabit.
    "ping": round(float(d.get("ping") or 0), 1),
    "down": round(float(d.get("download") or 0) / 1e6, 1),
    "up": round(float(d.get("upload") or 0) / 1e6, 1),
    "server": name or "?",
}, ensure_ascii=False))
PY
	exit 0
fi

if have speedtest; then
	roh="$(timeout 120 speedtest --format=json --accept-license --accept-gdpr 2>/dev/null)" || fail "Test failed"
	[ -n "$roh" ] || fail "Test failed"
	SPEED_JSON="$roh" python3 - <<'PY'
import json, os

d = json.loads(os.environ["SPEED_JSON"])
srv = d.get("server", {}) or {}
print(json.dumps({
    "ok": True,
    "ping": round(float((d.get("ping") or {}).get("latency") or 0), 1),
    # Ookla meldet Bytes je Sekunde.
    "down": round(float((d.get("download") or {}).get("bandwidth") or 0) * 8 / 1e6, 1),
    "up": round(float((d.get("upload") or {}).get("bandwidth") or 0) * 8 / 1e6, 1),
    "server": ", ".join(x for x in [srv.get("location"), srv.get("name")] if x) or "?",
}, ensure_ascii=False))
PY
	exit 0
fi

fail "speedtest-cli fehlt — sudo pacman -S speedtest-cli"
